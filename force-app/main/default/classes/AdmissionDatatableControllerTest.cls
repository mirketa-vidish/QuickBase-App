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
        opp.put('Admission_Date__c', Date.today());
        insert opp;
        return (Id) opp.get('Id');
    }

    private static void createReview(Id admissionId, String recordTypeDeveloperName) {
        Schema.SObjectType reviewType = Schema.getGlobalDescribe().get('Review__c');
        Map<String, Schema.RecordTypeInfo> rtInfos = reviewType.getDescribe().getRecordTypeInfosByDeveloperName();
        if (!rtInfos.containsKey(recordTypeDeveloperName)) {
            return;
        }
        SObject review = reviewType.newSObject();
        review.put('RecordTypeId', rtInfos.get(recordTypeDeveloperName).getRecordTypeId());
        review.put('Opportunity__c', admissionId);
        insert review;
    }

    @isTest
    static void testGetAdmissionsReturnsRowsWithReviewCounts() {
        Id admissionId = createAdmission('A-1001', 'Active');
        createReview(admissionId, 'Admission_Review');
        createReview(admissionId, 'Admission_Review');
        createReview(admissionId, 'Ongoing_Review');

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
        createAdmission('A-2002', 'Discharged');

        Map<String, String> filters = new Map<String, String>{
            'admissionId' => 'A-2002',
            'admissionDate' => String.valueOf(Date.today())
        };

        Test.startTest();
        AdmissionDatatableController.TableResult result = AdmissionDatatableController.getAdmissions(
            filters, null, null, null, null
        );
        Test.stopTest();

        System.assertEquals(1, result.totalRecords);
        System.assertEquals('A-2002', result.records[0].admissionId);
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
}
