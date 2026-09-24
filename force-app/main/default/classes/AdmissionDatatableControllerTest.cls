/**
 * Uses fully dynamic (Schema-based) SObject construction so this test class
 * compiles even before Review__c / the custom Opportunity fields exist in a
 * given org - it only fails at run time if the assumed schema is missing,
 * rather than blocking deployment of the rest of this package.
 */
@isTest
private class AdmissionDatatableControllerTest {

    private static Id createAdmission(String admissionId, String status) {
        SObject opp = Schema.getGlobalDescribe().get('Opportunity').newSObject();
        opp.put('Name', 'Test Admission ' + admissionId);
        opp.put('StageName', status);
        opp.put('CloseDate', Date.today().addMonths(1));
        opp.put('Admission_ID__c', admissionId);
        opp.put('MBC_ID__c', 'MBC-' + admissionId);
        opp.put('Admitted_Date__c', Date.today());
        insert opp;
        return (Id) opp.get('Id');
    }

    // supervisorName sets Supervisor__c - the before-insert trigger reads THIS
    // field to compute Combined_Text_Supervisor__c. Setting Combined_Text_Supervisor__c
    // directly in tests has no effect because the trigger always overwrites it.
    private static void createReview(Id admissionId, String recordTypeDeveloperName, String supervisorName) {
        Schema.SObjectType reviewType = Schema.getGlobalDescribe().get('Review__c');
        Map<String, Schema.RecordTypeInfo> rtInfos = reviewType.getDescribe().getRecordTypeInfosByDeveloperName();
        if (!rtInfos.containsKey(recordTypeDeveloperName)) {
            return;
        }
        SObject review = reviewType.newSObject();
        review.put('RecordTypeId', rtInfos.get(recordTypeDeveloperName).getRecordTypeId());
        review.put('Opportunity__c', admissionId);
        if (String.isNotBlank(supervisorName)) {
            review.put('Supervisor__c', supervisorName);
        }
        insert review;
    }

    @isTest
    static void testGetAdmissionsReturnsRowsWithReviewCounts() {
        Id admissionId = createAdmission('A-1001', 'Active');
        createReview(admissionId, 'Admission_Review', null);
        createReview(admissionId, 'Admission_Review', null);
        createReview(admissionId, 'Ongoing_Review', null);

        Test.startTest();
        AdmissionDatatableController.TableResult result = AdmissionDatatableController.getAdmissions(
            null, 'admissionId', 'ASC', 1, 10
        );
        Test.stopTest();

        System.assertEquals(1, result.totalRecords);
        System.assertEquals(1, result.records.size());
        AdmissionDatatableController.AdmissionRow row = result.records[0];
        System.assertEquals(admissionId, row.id);
        System.assertEquals(2, row.admissionReviewCount);
        System.assertEquals(1, row.ongoingReviewCount);
        System.assertEquals(3, row.allReviewCount);
    }

    @isTest
    static void testGetAdmissionsAppliesTextAndDateFilters() {
        createAdmission('A-2001', 'Active');
        Id secondId = createAdmission('A-2002', 'Discharged');

        Map<String, String> filters = new Map<String, String>{
            'admissionId' => secondId,
            'admissionDate' => String.valueOf(Date.today())
        };

        Test.startTest();
        AdmissionDatatableController.TableResult result = AdmissionDatatableController.getAdmissions(
            filters, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, result.totalRecords);
        System.assertEquals(secondId, result.records[0].id);
    }

    @isTest
    static void testGetAdmissionsWithNoArgsUsesDefaults() {
        createAdmission('A-3001', 'Active');

        Test.startTest();
        AdmissionDatatableController.TableResult result = AdmissionDatatableController.getAdmissions(
            null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, result.totalRecords);
    }

    @isTest
    static void testExportAdmissionsReturnsAllMatchingRowsUnpaginated() {
        createAdmission('A-4001', 'Active');
        createAdmission('A-4002', 'Active');

        Test.startTest();
        List<AdmissionDatatableController.AdmissionRow> rows = AdmissionDatatableController.exportAdmissions(
            null, null, null
        );
        Test.stopTest();

        System.assertEquals(2, rows.size());
    }

    @isTest
    static void testExportAdmissionsAppliesFilters() {
        createAdmission('A-5001', 'Active');
        Id secondId = createAdmission('A-5002', 'Discharged');

        Map<String, String> filters = new Map<String, String>{ 'admissionId' => secondId };

        Test.startTest();
        List<AdmissionDatatableController.AdmissionRow> rows = AdmissionDatatableController.exportAdmissions(
            filters, null, null
        );
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(secondId, rows[0].id);
    }

    @isTest
    static void testCombinedTextSupervisorFromMostRecentReview() {
        Id admissionId = createAdmission('A-6001', 'Active');
        // Supervisor__c is a restricted picklist - must use a real org value.
        // The trigger joins ALL unique Supervisor__c values across siblings with
        // '; ' and stamps Combined_Text_Supervisor__c. Using the same value for
        // both Reviews so the result is a single clean name to assert against.
        createReview(admissionId, 'Admission_Review', 'John Dyben');
        createReview(admissionId, 'Ongoing_Review',   'John Dyben');

        Test.startTest();
        AdmissionDatatableController.TableResult result = AdmissionDatatableController.getAdmissions(
            null, 'admissionId', 'ASC', 1, 10
        );
        Test.stopTest();

        System.assertEquals(1, result.records.size());
        AdmissionDatatableController.AdmissionRow row = result.records[0];
        // The trigger stamps Combined_Text_Supervisor__c = 'John Dyben' on every
        // Review for this Admission; the controller picks it from the most recent one.
        System.assertEquals('John Dyben', row.combinedTextSupervisor,
            'Expected supervisor stamped by trigger from Supervisor__c field');
    }

    @isTest
    static void testCombinedTextSupervisorIsNullWhenNoReviewsExist() {
        createAdmission('A-7001', 'Active');
        // No reviews created - supervisor column should be blank.

        Test.startTest();
        AdmissionDatatableController.TableResult result = AdmissionDatatableController.getAdmissions(
            null, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, result.records.size());
        System.assertNotEquals(null, result.records[0], 'Row should still be returned');
        System.assertEquals(null, result.records[0].combinedTextSupervisor,
            'Supervisor should be null when no Reviews exist');
    }
}