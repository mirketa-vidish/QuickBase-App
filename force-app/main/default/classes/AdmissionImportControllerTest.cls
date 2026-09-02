@isTest
private class AdmissionImportControllerTest {

    private static Id createAdmission() {
        Opportunity opp = new Opportunity(
            Name = 'Original Name',
            StageName = 'Active',
            CloseDate = Date.today().addMonths(1)
        );
        insert opp;
        return opp.Id;
    }

    @isTest
    static void testUpdateAdmissionsUpdatesMappedFields() {
        Id admissionId = createAdmission();

        Map<String, Object> row = new Map<String, Object>{
            'opportunityId' => admissionId,
            'mbcId' => 'A79JN',
            'patientName' => 'Sarah Midgley',
            'clientFirstName' => 'Sarah',
            'clientLastName' => 'Midgley',
            'admittedDate' => '2026-06-22',
            'dischargeDate' => null,
            'program' => 'DNCH',
            'admittedLevelOfCare' => 'Detox',
            'currentServiceFacilityName' => 'Hanley Center Counseling',
            'realm' => 'Origins Behavioral HealthCare of Florida, LLC'
        };

        Test.startTest();
        List<AdmissionImportController.ImportRowResult> results = AdmissionImportController.updateAdmissions(
            new List<Map<String, Object>>{ row }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);

        Opportunity updated = [
            SELECT Name, Client_First_Name__c, Client_Last_Name__c, Program__c
            FROM Opportunity WHERE Id = :admissionId
        ];
        System.assertEquals('Sarah Midgley', updated.Name);
        System.assertEquals('Sarah', updated.Client_First_Name__c);
        System.assertEquals('Midgley', updated.Client_Last_Name__c);
        System.assertEquals('DNCH', updated.Program__c);
    }

    @isTest
    static void testUpdateAdmissionsReportsInvalidId() {
        Map<String, Object> row = new Map<String, Object>{
            'opportunityId' => 'not-a-real-id',
            'patientName' => 'Someone'
        };

        Test.startTest();
        List<AdmissionImportController.ImportRowResult> results = AdmissionImportController.updateAdmissions(
            new List<Map<String, Object>>{ row }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
    }

    @isTest
    static void testUpdateAdmissionsReportsMissingId() {
        Map<String, Object> row = new Map<String, Object>{ 'patientName' => 'Someone' };

        Test.startTest();
        List<AdmissionImportController.ImportRowResult> results = AdmissionImportController.updateAdmissions(
            new List<Map<String, Object>>{ row }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
    }

    @isTest
    static void testUpdateAdmissionsWithNullRowsReturnsEmpty() {
        Test.startTest();
        List<AdmissionImportController.ImportRowResult> results = AdmissionImportController.updateAdmissions(null);
        Test.stopTest();

        System.assertEquals(0, results.size());
    }
}
