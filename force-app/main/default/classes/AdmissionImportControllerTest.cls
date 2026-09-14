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
            'mri' => '2978',
            'patientName' => 'Sarah Midgley',
            'clientFirstName' => 'Sarah',
            'clientLastName' => 'Midgley',
            'primaryCounselor' => 'Katie Hiatt',
            'admittedDate' => '2026-06-22',
            'dischargeDate' => null,
            'program' => 'DNCH',
            'admissionServiceFacility' => 'Hanley Center',
            'admittedLevelOfCare' => 'Detox',
            'currentServiceFacilityName' => 'Hanley Center Counseling',
            'currentLevelOfCare' => 'PHP',
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
            SELECT Name, Client_First_Name__c, Client_Last_Name__c, Program__c,
                MBC_ID__c, Sunwave_MRI_OBHFL__c, Primary_Counselor__c,
                Facility_Approved__c, Current_Service_Facility__c, Current_Level_Of_Care__c
            FROM Opportunity WHERE Id = :admissionId
        ];
        System.assertEquals('Sarah Midgley', updated.Name);
        System.assertEquals('Sarah', updated.Client_First_Name__c);
        System.assertEquals('Midgley', updated.Client_Last_Name__c);
        System.assertEquals('DNCH', updated.Program__c);
        System.assertEquals('2978', updated.Sunwave_MRI_OBHFL__c);
        System.assertEquals('Katie Hiatt', updated.Primary_Counselor__c);
        System.assertEquals('Hanley Center', updated.Facility_Approved__c);
        System.assertEquals('Hanley Center Counseling', updated.Current_Service_Facility__c);
        System.assertEquals('PHP', updated.Current_Level_Of_Care__c);
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