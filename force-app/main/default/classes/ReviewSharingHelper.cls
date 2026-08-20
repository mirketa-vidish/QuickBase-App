/**
 * Runs Review__c queries without record-level sharing enforcement, by
 * design: anyone who can see an Admission (Opportunity) should be able to
 * see all Review__c records linked to it and their counts, regardless of
 * Review__c's own sharing rules/ownership.
 *
 * Apex sharing (with/without sharing) is class-level only - it cannot be
 * toggled per method - so this is split out from AdmissionDatatableController
 * and ReviewListController, both of which stay "with sharing" for their own
 * Opportunity queries.
 */
public without sharing class ReviewSharingHelper {

    public static List<AggregateResult> getReviewCountsByAdmission(
        Set<Id> admissionIds,
        String reviewObject,
        String admissionLookupField
    ) {
        String query = 'SELECT ' + admissionLookupField + ' admissionId, RecordType.DeveloperName rtName, COUNT(Id) cnt ' +
            'FROM ' + reviewObject +
            ' WHERE ' + admissionLookupField + ' IN :admissionIds ' +
            'GROUP BY ' + admissionLookupField + ', RecordType.DeveloperName';
        Map<String, Object> binds = new Map<String, Object>{ 'admissionIds' => admissionIds };
        return Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
    }

    public static Integer countReviews(String reviewObject, String whereClause, Map<String, Object> binds) {
        String query = 'SELECT COUNT() FROM ' + reviewObject + whereClause;
        return Database.countQueryWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
    }

    public static List<SObject> queryReviews(String query, Map<String, Object> binds) {
        return Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
    }
}
