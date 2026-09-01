/**
 * Server-side paging/filtering/sorting for the Admissions datatable LWC, plus
 * per-Admission (Opportunity) review counts split by Review record type.
 *
 * All object/field API names referenced here are assumed to already exist in
 * the target org (per QuickBase migration). If any name differs, only the
 * constants/maps below need updating - the query itself is fully dynamic
 * (Database.queryWithBinds) so a mismatch fails at run time with a clear
 * error rather than blocking deployment of this class.
 */
public with sharing class AdmissionDatatableController {

    // Review__c object + lookup back to the Admission (Opportunity).
    private static final String REVIEW_OBJECT = 'Review__c';
    private static final String REVIEW_ADMISSION_LOOKUP = 'Opportunity__c';

    // Review__c RecordType.DeveloperName values for the two review types.
    private static final String RT_ADMISSION_REVIEW = 'Admission_Review';
    private static final String RT_ONGOING_REVIEW = 'Ongoing_Review';

    // Patient Name is not a single field - it's the concatenation of these
    // three Opportunity text fields (first/middle/last), in this order.
    private static final List<String> PATIENT_NAME_FIELDS = new List<String>{
        'Client_First_Name__c', 'Client_Middle_Name__c', 'Client_Last_Name__c'
    };

    // Current Level Of Care is not a single field either - it's
    // Discharged_Level_of_Care__c when the Admission has a Discharge Date,
    // otherwise Admitted_Level_of_Care__c.
    private static final String LOC_DISCHARGED_FIELD = 'Discharged_Level_of_Care__c';
    private static final String LOC_ADMITTED_FIELD = 'Admitted_Level_of_Care__c';

    // Logical column key -> Opportunity field API name (used for both the
    // SELECT list and for sorting).
    private static final Map<String, String> SORT_FIELD_MAP = new Map<String, String>{
        'admissionId' => 'Admission_ID__c',
        'mbcId' => 'MBC_ID__c',
        'admissionDate' => 'Admission_Date__c',
        'dischargeDate' => 'Discharge_Date__c',
        'status' => 'Status__c',
        'patientName' => 'Client_Last_Name__c, Client_First_Name__c',
        'program' => 'Program__c',
        'currentServiceFacility' => 'Facility_Approved__c',
        // No single field to sort by - falls back to the default sort field.
        'realm' => 'Anticipated_Realm__c',
        'primaryCounselor' => 'CreatedBy.Name',
        'combinedTextSupervisor' => 'LastModifiedBy.Name',
        'mri' => 'MRI__c'
    };

    // Logical filter key -> Opportunity field API name, for simple
    // case-insensitive "contains" text filters. Patient Name and Current
    // Level Of Care are handled separately in buildWhereClause since each
    // spans more than one underlying field.
    private static final Map<String, String> TEXT_FILTER_FIELDS = new Map<String, String>{
        'admissionId' => 'Admission_ID__c',
        'mbcId' => 'MBC_ID__c',
        'status' => 'Status__c',
        'program' => 'Program__c',
        'currentServiceFacility' => 'Facility_Approved__c',
        'realm' => 'Anticipated_Realm__c',
        'primaryCounselor' => 'CreatedBy.Name',
        'combinedTextSupervisor' => 'LastModifiedBy.Name',
        'mri' => 'MRI__c'
    };

    // Logical filter key -> Opportunity date field API name, matched by
    // exact date (one filter box per column, same as the QuickBase table).
    private static final Map<String, String> DATE_FILTER_FIELDS = new Map<String, String>{
        'admissionDate' => 'Admission_Date__c',
        'dischargeDate' => 'Discharge_Date__c'
    };

    private static final Integer DEFAULT_PAGE_SIZE = 25;
    // Safety cap on CSV export size - keeps a single export well inside
    // governor limits regardless of how many Admissions match the filters.
    private static final Integer EXPORT_MAX_ROWS = 2000;

    public class TableResult {
        @AuraEnabled public List<AdmissionRow> records;
        @AuraEnabled public Integer totalRecords;
    }

    public class AdmissionRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String admissionId;
        @AuraEnabled public String mbcId;
        @AuraEnabled public Date admissionDate;
        @AuraEnabled public Date dischargeDate;
        @AuraEnabled public String status;
        @AuraEnabled public String patientName;
        @AuraEnabled public String program;
        @AuraEnabled public String currentServiceFacility;
        @AuraEnabled public String currentLevelOfCare;
        @AuraEnabled public String realm;
        @AuraEnabled public String primaryCounselor;
        @AuraEnabled public String combinedTextSupervisor;
        @AuraEnabled public String mri;
        @AuraEnabled public Integer admissionReviewCount = 0;
        @AuraEnabled public Integer ongoingReviewCount = 0;
        @AuraEnabled public Integer allReviewCount = 0;
    }

    @AuraEnabled
    public static TableResult getAdmissions(
        Map<String, String> filters,
        String sortField,
        String sortDirection,
        Integer pageNumber,
        Integer pageSize
    ) {
        // Plain scalar/Map parameters, not a wrapper request object - a
        // custom wrapper class parameter here previously deserialized to an
        // empty/null instance when called imperatively from the LWC (the
        // same issue confirmed and fixed in ReviewListController), which is
        // why filtering silently did nothing while pagination/sorting
        // appeared to work (they have safe defaults; filters does not).
        Integer effectivePageSize = (pageSize != null && pageSize > 0) ? pageSize : DEFAULT_PAGE_SIZE;
        Integer effectivePageNumber = (pageNumber != null && pageNumber > 0) ? pageNumber : 1;
        Integer offset = (effectivePageNumber - 1) * effectivePageSize;

        Map<String, Object> binds = new Map<String, Object>();
        String whereClause = buildWhereClause(filters, binds);

        String orderByField = SORT_FIELD_MAP.containsKey(sortField)
            ? SORT_FIELD_MAP.get(sortField)
            : 'Admission_Date__c';
        String orderByDir = 'ASC'.equalsIgnoreCase(sortDirection) ? 'ASC' : 'DESC';

        String countQuery = 'SELECT COUNT() FROM Opportunity' + whereClause;
        Integer total = Database.countQueryWithBinds(countQuery, binds, AccessLevel.USER_MODE);

        TableResult result = new TableResult();
        result.records = fetchRows(whereClause, binds, orderByField, orderByDir, effectivePageSize, offset);
        result.totalRecords = total;
        return result;
    }

    /**
     * All matching Admissions for the current filters/sort (capped at
     * EXPORT_MAX_ROWS), for the Export button - not paginated like
     * getAdmissions since an export needs every matching row, not just the
     * current page.
     */
    @AuraEnabled
    public static List<AdmissionRow> exportAdmissions(
        Map<String, String> filters,
        String sortField,
        String sortDirection
    ) {
        Map<String, Object> binds = new Map<String, Object>();
        String whereClause = buildWhereClause(filters, binds);

        String orderByField = SORT_FIELD_MAP.containsKey(sortField)
            ? SORT_FIELD_MAP.get(sortField)
            : 'Admission_Date__c';
        String orderByDir = 'ASC'.equalsIgnoreCase(sortDirection) ? 'ASC' : 'DESC';

        return fetchRows(whereClause, binds, orderByField, orderByDir, EXPORT_MAX_ROWS, 0);
    }

    private static List<AdmissionRow> fetchRows(
        String whereClause,
        Map<String, Object> binds,
        String orderByField,
        String orderByDir,
        Integer limitSize,
        Integer offset
    ) {
        Map<String, Object> dataBinds = new Map<String, Object>(binds);
        dataBinds.put('limitSize', limitSize);
        dataBinds.put('offsetSize', offset);

        String dataQuery = 'SELECT Id, Admission_ID__c, MBC_ID__c, Admission_Date__c, Discharge_Date__c, Status__c, ' +
            'Client_First_Name__c, Client_Middle_Name__c, Client_Last_Name__c, ' +
            'Program__c, Facility_Approved__c, Admitted_Level_of_Care__c, Discharged_Level_of_Care__c, Anticipated_Realm__c, ' +
            'CreatedBy.Name, LastModifiedBy.Name, MRI__c ' +
            'FROM Opportunity' + whereClause +
            ' ORDER BY ' + orderByField + ' ' + orderByDir +
            ' LIMIT :limitSize OFFSET :offsetSize';

        List<SObject> opps = Database.queryWithBinds(dataQuery, dataBinds, AccessLevel.USER_MODE);

        List<AdmissionRow> rows = new List<AdmissionRow>();
        Map<Id, AdmissionRow> rowById = new Map<Id, AdmissionRow>();
        for (SObject o : opps) {
            AdmissionRow row = new AdmissionRow();
            row.id = (Id) o.get('Id');
            row.admissionId = toStringValue(o.get('Admission_ID__c'));
            row.mbcId = toStringValue(o.get('MBC_ID__c'));
            row.admissionDate = (Date) o.get('Admission_Date__c');
            row.dischargeDate = (Date) o.get('Discharge_Date__c');
            row.status = toStringValue(o.get('Status__c'));
            row.patientName = buildPatientName(o);
            row.program = toStringValue(o.get('Program__c'));
            row.currentServiceFacility = toStringValue(o.get('Facility_Approved__c'));
            row.currentLevelOfCare = row.dischargeDate != null
                ? toStringValue(o.get(LOC_DISCHARGED_FIELD))
                : toStringValue(o.get(LOC_ADMITTED_FIELD));
            row.realm = toStringValue(o.get('Anticipated_Realm__c'));
            row.primaryCounselor = getRelatedName(o, 'CreatedBy');
            row.combinedTextSupervisor = getRelatedName(o, 'LastModifiedBy');
            row.mri = toStringValue(o.get('MRI__c'));
            rows.add(row);
            rowById.put(row.id, row);
        }

        if (!rowById.isEmpty()) {
            String reviewQuery = 'SELECT ' + REVIEW_ADMISSION_LOOKUP + ' admissionId, RecordType.DeveloperName rtName, COUNT(Id) cnt ' +
                'FROM ' + REVIEW_OBJECT +
                ' WHERE ' + REVIEW_ADMISSION_LOOKUP + ' IN :admissionIds ' +
                'GROUP BY ' + REVIEW_ADMISSION_LOOKUP + ', RecordType.DeveloperName';
            Map<String, Object> reviewBinds = new Map<String, Object>{ 'admissionIds' => rowById.keySet() };
            // SYSTEM_MODE by design: anyone who can see an Admission can see
            // its review counts regardless of Review__c's own sharing rules
            // (kept consistent with ReviewListController, which powers the
            // filtered list these counts link to).
            List<AggregateResult> reviewCounts = Database.queryWithBinds(reviewQuery, reviewBinds, AccessLevel.SYSTEM_MODE);

            for (AggregateResult ar : reviewCounts) {
                Id admissionId = (Id) ar.get('admissionId');
                String rtName = (String) ar.get('rtName');
                Integer cnt = (Integer) ar.get('cnt');
                AdmissionRow row = rowById.get(admissionId);
                if (row == null) {
                    continue;
                }
                row.allReviewCount += cnt;
                if (RT_ADMISSION_REVIEW.equalsIgnoreCase(rtName)) {
                    row.admissionReviewCount += cnt;
                } else if (RT_ONGOING_REVIEW.equalsIgnoreCase(rtName)) {
                    row.ongoingReviewCount += cnt;
                }
            }
        }

        return rows;
    }

    private static String buildWhereClause(Map<String, String> filters, Map<String, Object> binds) {
        if (filters == null || filters.isEmpty()) {
            return '';
        }
        List<String> conditions = new List<String>();
        Integer i = 0;
        for (String key : filters.keySet()) {
            String value = filters.get(key);
            if (String.isBlank(value)) {
                continue;
            }
            if (key == 'patientName') {
                String bindName = 'v' + i++;
                List<String> orParts = new List<String>();
                for (String nameField : PATIENT_NAME_FIELDS) {
                    orParts.add(nameField + ' LIKE :' + bindName);
                }
                conditions.add('(' + String.join(orParts, ' OR ') + ')');
                binds.put(bindName, '%' + value + '%');
            } else if (key == 'currentLevelOfCare') {
                String bindName = 'v' + i++;
                conditions.add('(' + LOC_ADMITTED_FIELD + ' LIKE :' + bindName + ' OR ' + LOC_DISCHARGED_FIELD + ' LIKE :' + bindName + ')');
                binds.put(bindName, '%' + value + '%');
            } else if (TEXT_FILTER_FIELDS.containsKey(key)) {
                String bindName = 'v' + i++;
                conditions.add(TEXT_FILTER_FIELDS.get(key) + ' LIKE :' + bindName);
                binds.put(bindName, '%' + value + '%');
            } else if (DATE_FILTER_FIELDS.containsKey(key)) {
                Date parsed = parseDate(value);
                if (parsed != null) {
                    String bindName = 'v' + i++;
                    conditions.add(DATE_FILTER_FIELDS.get(key) + ' = :' + bindName);
                    binds.put(bindName, parsed);
                }
            }
        }
        return conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
    }

    private static Date parseDate(String value) {
        try {
            return Date.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static String toStringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static String getRelatedName(SObject record, String relationshipName) {
        SObject related = record.getSObject(relationshipName);
        return related == null ? null : (String) related.get('Name');
    }

    private static String buildPatientName(SObject record) {
        List<String> parts = new List<String>();
        for (String nameField : PATIENT_NAME_FIELDS) {
            String value = toStringValue(record.get(nameField));
            if (String.isNotBlank(value)) {
                parts.add(value);
            }
        }
        return parts.isEmpty() ? null : String.join(parts, ' ');
    }
}