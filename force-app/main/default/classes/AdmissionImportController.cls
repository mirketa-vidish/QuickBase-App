/**
 * Bulk-updates existing Opportunity (Admission) records from an uploaded
 * CSV, per the client-provided mapping sheet (Salesforce Chart Review
 * Upload Sample.csv). Always an UPDATE - every row must carry the target
 * record's actual Salesforce Id (the CSV's "Opportunity Legacy Id" column);
 * this never creates new records.
 *
 * Column -> field mapping (blank cells in the mapping sheet are not
 * imported at all):
 *   Opportunity Legacy Id      -> Id (match key, not a field to set)
 *   Mbc Id                     -> MBC_ID__c
 *   Mri                        -> (not mapped)
 *   Patient Name               -> Name
 *   Patient First Name         -> Client_First_Name__c
 *   Patient Last Name          -> Client_Last_Name__c
 *   Primary Counselor          -> (not mapped)
 *   Admission Date             -> Admitted_Date__c
 *   Discharge Date             -> Discharge_Date__c
 *   Program                    -> Program__c
 *   Admission Service Facility -> (not mapped)
 *   Admission Level Of Care    -> Admitted_Level_of_Care__c
 *   Current Service Facility Name -> Facility_Approved__c
 *   Current Level Of Care      -> (not mapped)
 *   Realm                      -> Anticipated_Realm__c
 *
 * rows is List<Map<String, Object>> rather than a custom wrapper class -
 * a custom Apex class used directly as an @AuraEnabled parameter has
 * previously deserialized to an empty/null instance when called
 * imperatively from LWC in this org (see ReviewListController and
 * AdmissionDatatableController); plain Lists/Maps of primitives have not
 * shown that issue, so that's what's used here for the input side too.
 */
public with sharing class AdmissionImportController {

    public class ImportRowResult {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String opportunityId;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
    }

    @AuraEnabled
    public static List<ImportRowResult> updateAdmissions(List<Map<String, Object>> rows) {
        List<ImportRowResult> results = new List<ImportRowResult>();
        if (rows == null) {
            return results;
        }

        List<Opportunity> toUpdate = new List<Opportunity>();
        List<Integer> rowNumberByIndex = new List<Integer>();

        Integer rowNumber = 0;
        for (Map<String, Object> row : rows) {
            rowNumber++;
            String opportunityId = (String) row.get('opportunityId');

            if (String.isBlank(opportunityId)) {
                results.add(buildResult(rowNumber, opportunityId, false, 'Missing Opportunity Legacy Id (Salesforce record Id).'));
                continue;
            }

            Opportunity opp;
            try {
                opp = new Opportunity(Id = (Id) opportunityId);
            } catch (Exception e) {
                results.add(buildResult(rowNumber, opportunityId, false, 'Invalid Salesforce Id: ' + opportunityId));
                continue;
            }

            putIfNotBlank(opp, 'MBC_ID__c', (String) row.get('mbcId'));
            putIfNotBlank(opp, 'Name', (String) row.get('patientName'));
            putIfNotBlank(opp, 'Client_First_Name__c', (String) row.get('clientFirstName'));
            putIfNotBlank(opp, 'Client_Last_Name__c', (String) row.get('clientLastName'));
            putDateIfValid(opp, 'Admitted_Date__c', (String) row.get('admittedDate'));
            putDateIfValid(opp, 'Discharge_Date__c', (String) row.get('dischargeDate'));
            putIfNotBlank(opp, 'Program__c', (String) row.get('program'));
            putIfNotBlank(opp, 'Admitted_Level_of_Care__c', (String) row.get('admittedLevelOfCare'));
            putIfNotBlank(opp, 'Facility_Approved__c', (String) row.get('currentServiceFacilityName'));
            putIfNotBlank(opp, 'Anticipated_Realm__c', (String) row.get('realm'));

            toUpdate.add(opp);
            rowNumberByIndex.add(rowNumber);
        }

        if (!toUpdate.isEmpty()) {
            List<Database.SaveResult> saveResults = Database.update(toUpdate, false, AccessLevel.USER_MODE);
            for (Integer i = 0; i < saveResults.size(); i++) {
                Database.SaveResult sr = saveResults[i];
                String errorMessage = null;
                if (!sr.isSuccess() && !sr.getErrors().isEmpty()) {
                    errorMessage = sr.getErrors()[0].getMessage();
                }
                results.add(buildResult(rowNumberByIndex[i], toUpdate[i].Id, sr.isSuccess(), errorMessage));
            }
        }

        return results;
    }

    private static ImportRowResult buildResult(Integer rowNumber, String opportunityId, Boolean success, String errorMessage) {
        ImportRowResult result = new ImportRowResult();
        result.rowNumber = rowNumber;
        result.opportunityId = opportunityId;
        result.success = success;
        result.errorMessage = errorMessage;
        return result;
    }

    private static void putIfNotBlank(Opportunity opp, String fieldName, String value) {
        if (String.isNotBlank(value)) {
            opp.put(fieldName, value);
        }
    }

    private static void putDateIfValid(Opportunity opp, String fieldName, String isoDateString) {
        if (String.isBlank(isoDateString)) {
            return;
        }
        try {
            opp.put(fieldName, Date.valueOf(isoDateString));
        } catch (Exception e) {
            // Malformed date for this one field - leave it unset rather
            // than failing the whole row over a single bad value.
        }
    }
}
