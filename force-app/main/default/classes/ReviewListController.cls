/**
 * Server-side paging for the custom Review__c list shown when a user clicks
 * Reviews / a review count on an Admission row. Always scoped to one
 * Admission (Opportunity), optionally further scoped to one review record
 * type (Admission Review vs Ongoing Review).
 *
 * Chart - MBC ID, Chart - Primary Counselor and Chart - Realm have no
 * dedicated field on Review__c, so they're pulled directly through the
 * Opportunity__c relationship - the same three fields already used for the
 * Admissions datatable's own MBC ID / Primary Counselor / Realm columns.
 *
 * The Review__c queries run as AccessLevel.SYSTEM_MODE (bypassing FLS) so
 * this list always matches the review counts shown on the Admissions
 * datatable, which are computed the same way in AdmissionDatatableController.
 *
 * getReviews takes plain scalar parameters rather than a wrapper request
 * object - a wrapper class here previously deserialized to an all-null
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
        @AuraEnabled public Date reviewDate;
        @AuraEnabled public String reviewType;
        @AuraEnabled public String supervisor;
        @AuraEnabled public String chartMbcId;
        @AuraEnabled public String chartPatientName;
        @AuraEnabled public String chartCurrentServiceFacility;
        @AuraEnabled public String chartPrimaryCounselor;
        @AuraEnabled public String chartRealm;
        @AuraEnabled public Id chartId;
        @AuraEnabled public String chartName;
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

        String dataQuery = 'SELECT Id, Review_Date__c, RecordType.Name, Supervisor__c, ' +
            'Patient_Name__c, Current_Service_Facility__c, ' +
            'Opportunity__c, Opportunity__r.MBC_ID__c, Opportunity__r.CreatedBy.Name, Opportunity__r.Anticipated_Realm__c ' +
            'FROM ' + REVIEW_OBJECT + whereClause +
            ' ORDER BY Review_Date__c DESC' +
            ' LIMIT :limitSize OFFSET :offsetSize';

        List<SObject> reviews = Database.queryWithBinds(dataQuery, dataBinds, AccessLevel.SYSTEM_MODE);

        for (SObject r : reviews) {
            ReviewRow row = new ReviewRow();
            row.id = (Id) r.get('Id');
            row.reviewDate = (Date) r.get('Review_Date__c');
            row.reviewType = getRelatedField(r, 'RecordType', 'Name');
            row.supervisor = (String) r.get('Supervisor__c');
            row.chartPatientName = (String) r.get('Patient_Name__c');
            row.chartCurrentServiceFacility = (String) r.get('Current_Service_Facility__c');
            row.chartId = (Id) r.get('Opportunity__c');

            SObject chart = r.getSObject('Opportunity__r');
            row.chartMbcId = chart == null ? null : (String) chart.get('MBC_ID__c');
            row.chartRealm = chart == null ? null : (String) chart.get('Anticipated_Realm__c');
            row.chartPrimaryCounselor = chart == null ? null : getRelatedField(chart, 'CreatedBy', 'Name');
            row.chartName = row.chartPatientName;

            result.records.add(row);
        }

        return result;
    }

    private static String getRelatedField(SObject record, String relationshipName, String fieldName) {
        SObject related = record.getSObject(relationshipName);
        return related == null ? null : (String) related.get(fieldName);
    }
}
