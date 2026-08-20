/**
 * Uses fully dynamic (Schema-based) SObject construction so this test class
 * compiles even before Review__c's real fields are confirmed - it only fails
 * at run time if the assumed schema is missing, rather than blocking
 * deployment of the rest of this package.
 */
@isTest
private class ReviewListControllerTest {

    private static Id createAdmission() {
        SObject opp = Schema.getGlobalDescribe().get('Opportunity').newSObject();
        opp.put('Name', 'Test Admission');
        opp.put('StageName', 'Active');
        opp.put('CloseDate', Date.today().addMonths(1));
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
    static void testGetReviewsFiltersByAdmissionAndType() {
        Id admissionId = createAdmission();
        createReview(admissionId, 'Admission_Review');
        createReview(admissionId, 'Admission_Review');
        createReview(admissionId, 'Ongoing_Review');

        Test.startTest();
        ReviewListController.ReviewListResult result = ReviewListController.getReviews(admissionId, 'Admission_Review', 1, 25);
        Test.stopTest();

        System.assertEquals(2, result.totalRecords);
    }

    @isTest
    static void testGetReviewsWithoutTypeReturnsAll() {
        Id admissionId = createAdmission();
        createReview(admissionId, 'Admission_Review');
        createReview(admissionId, 'Ongoing_Review');

        Test.startTest();
        ReviewListController.ReviewListResult result = ReviewListController.getReviews(admissionId, null, null, null);
        Test.stopTest();

        System.assertEquals(2, result.totalRecords);
    }

    @isTest
    static void testGetReviewsWithBlankAdmissionReturnsEmpty() {
        Test.startTest();
        ReviewListController.ReviewListResult result = ReviewListController.getReviews(null, null, null, null);
        Test.stopTest();

        System.assertEquals(0, result.totalRecords);
        System.assertEquals(0, result.records.size());
    }
}
