/**
 * Server-side paging for the custom Review__c list shown when a user clicks
 * Reviews / a review count on an Admission row. Always scoped to one
 * Admission (Opportunity), optionally further scoped to one review record
 * type (Admission Review vs Ongoing Review).
 *
 * The column set below is a safe generic default (fields virtually
 * guaranteed to exist on any custom object) since Review__c's real field
 * list wasn't available locally. Update the SELECT list and ReviewRow
 * mapping below once the real columns are known - the query is fully
 * dynamic (Database.queryWithBinds) so this doesn't block deployment.
 *
 * The Review__c queries run as AccessLevel.SYSTEM_MODE (bypassing FLS) so
 * this list always matches the review counts shown on the Admissions
 * datatable, which are computed the same way in AdmissionDatatableController.
 *
 * getReviews takes plain scalar parameters rather than a wrapper request
 * object - a wrapper class here was silently deserializing to an all-null
 * instance when called imperatively from the reviewsListModal LWC (confirmed
 * via Anonymous Apex: the exact same values worked fine when the method was
 * called directly, so the issue was specific to the LWC/Aura parameter
 * bridge for that wrapper, not the query logic itself).
 */
public with sharing class ReviewListController {

    private static final String REVIEW_OBJECT = 'Review__c';
    private static final String REVIEW_ADMISSION_LOOKUP = 'Opportunity__c';
    private static final Integer DEFAULT_PAGE_SIZE = 25;

    public class ReviewListResult {
        @AuraEnabled public List<ReviewRow> records;
        @AuraEnabled public Integer totalRecords;
    }

    public class ReviewRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String recordTypeName;
        @AuraEnabled public String createdByName;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Datetime lastModifiedDate;
    }

    @AuraEnabled
    public static ReviewListResult getReviews(
        String admissionId,
        String reviewType,
        Integer pageNumber,
        Integer pageSize
    ) {
        ReviewListResult result = new ReviewListResult();
        result.records = new List<ReviewRow>();
        result.totalRecords = 0;

        if (String.isBlank(admissionId)) {
            return result;
        }

        Integer effectivePageSize = (pageSize != null && pageSize > 0) ? pageSize : DEFAULT_PAGE_SIZE;
        Integer effectivePageNumber = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;
        Integer offset = (effectivePageNumber - 1) * effectivePageSize;

        String whereClause = ' WHERE ' + REVIEW_ADMISSION_LOOKUP + ' = :admissionId';
        Map<String, Object> binds = new Map<String, Object>{ 'admissionId' => admissionId };

        if (String.isNotBlank(reviewType)) {
            whereClause += ' AND RecordType.DeveloperName = :reviewType';
            binds.put('reviewType', reviewType);
        }

        String countQuery = 'SELECT COUNT() FROM ' + REVIEW_OBJECT + whereClause;
        result.totalRecords = Database.countQueryWithBinds(countQuery, binds, AccessLevel.SYSTEM_MODE);

        Map<String, Object> dataBinds = new Map<String, Object>(binds);
        dataBinds.put('limitSize', effectivePageSize);
        dataBinds.put('offsetSize', offset);

        String dataQuery = 'SELECT Id, Name, RecordType.Name, CreatedBy.Name, CreatedDate, LastModifiedDate ' +
            'FROM ' + REVIEW_OBJECT + whereClause +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT :limitSize OFFSET :offsetSize';

        List<SObject> reviews = Database.queryWithBinds(dataQuery, dataBinds, AccessLevel.SYSTEM_MODE);

        for (SObject r : reviews) {
            ReviewRow row = new ReviewRow();
            row.id = (Id) r.get('Id');
            row.name = (String) r.get('Name');
            row.recordTypeName = getRelatedField(r, 'RecordType', 'Name');
            row.createdByName = getRelatedField(r, 'CreatedBy', 'Name');
            row.createdDate = (Datetime) r.get('CreatedDate');
            row.lastModifiedDate = (Datetime) r.get('LastModifiedDate');
            result.records.add(row);
        }

        return result;
    }

    private static String getRelatedField(SObject record, String relationshipName, String fieldName) {
        SObject related = record.getSObject(relationshipName);
        return related == null ? null : (String) related.get(fieldName);
    }
}
