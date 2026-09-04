import LightningModal from 'lightning/modal';
import updateAdmissions from '@salesforce/apex/AdmissionImportController.updateAdmissions';

// CSV header (trimmed, lower-cased) -> internal row key. Headers not listed
// here (Mri, Primary Counselor, Admission Service Facility, Current Level
// Of Care) are present in the sample file but have no Salesforce field in
// the mapping sheet, so they're intentionally ignored on import.
const HEADER_MAP = {
    'opportunity legacy id': 'opportunityId',
    'mbc id': 'mbcId',
    'patient name': 'patientName',
    'patient first name': 'clientFirstName',
    'patient last name': 'clientLastName',
    'admission date': 'admittedDate',
    'discharge date': 'dischargeDate',
    program: 'program',
    'admission level of care': 'admittedLevelOfCare',
    'current service facility name': 'currentServiceFacilityName',
    realm: 'realm'
};
const DATE_FIELDS = new Set(['admittedDate', 'dischargeDate']);
// Some automation on Opportunity (a trigger/Flow outside this component's
// control) appears to run a SOQL query per record rather than being
// bulkified, which trips the 100-queries-per-transaction limit right around
// 100 rows in a single Database.update(). Each separate imperative Apex
// call is its own transaction with governor limits reset, so sending rows
// in smaller chunks across multiple sequential calls works around it
// regardless of what's actually consuming those queries.
const IMPORT_CHUNK_SIZE = 50;

export default class ImportAdmissionsModal extends LightningModal {
    fileName;
    parsedRows = [];
    results = [];
    isProcessing = false;
    hasImported = false;
    errorMessage;
    progressLabel;

    get hasFile() {
        return this.parsedRows.length > 0;
    }

    get recordCount() {
        return this.parsedRows.length;
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get successCount() {
        return this.results.filter((r) => r.success).length;
    }

    get failureCount() {
        return this.results.filter((r) => !r.success).length;
    }

    get hasFailures() {
        return this.failureCount > 0;
    }

    get failedResults() {
        return this.results.filter((r) => !r.success);
    }

    get isImportDisabled() {
        return this.isProcessing || !this.hasFile;
    }

    async handleFileChange(event) {
        const file = event.target.files[0];
        if (!file) {
            return;
        }
        this.errorMessage = undefined;
        this.results = [];
        this.hasImported = false;
        this.fileName = file.name;

        try {
            const text = await file.text();
            const csvRows = this.parseCsv(text);
            if (csvRows.length < 2) {
                this.errorMessage = 'The file has no data rows.';
                this.parsedRows = [];
                return;
            }
            this.parsedRows = this.buildImportRows(csvRows);
            if (this.parsedRows.length === 0) {
                this.errorMessage = 'No valid data rows were found in the file.';
            }
        } catch (error) {
            this.errorMessage = 'Could not read the selected file.';
            this.parsedRows = [];
        }
    }

    async handleImportClick() {
        this.isProcessing = true;
        this.errorMessage = undefined;
        this.results = [];

        const chunks = this.chunkRows(this.parsedRows, IMPORT_CHUNK_SIZE);
        try {
            for (let i = 0; i < chunks.length; i++) {
                this.progressLabel = chunks.length > 1
                    ? `Importing ${i + 1} of ${chunks.length} batches...`
                    : undefined;
                // Sequential, not Promise.all - each call must complete
                // (and its transaction end) before the next one starts.
                // eslint-disable-next-line no-await-in-loop
                const chunkResults = await updateAdmissions({ rows: chunks[i] });
                // Each Apex call restarts its row-number counter at 1, so
                // offset it back to the row's real position in the full file.
                const offset = i * IMPORT_CHUNK_SIZE;
                this.results = this.results.concat(
                    chunkResults.map((r) => ({ ...r, rowNumber: r.rowNumber + offset }))
                );
            }
            this.hasImported = true;
        } catch (error) {
            this.errorMessage = error?.body?.message || 'Import failed.';
        } finally {
            this.progressLabel = undefined;
            this.isProcessing = false;
        }
    }

    chunkRows(rows, size) {
        const chunks = [];
        for (let i = 0; i < rows.length; i += size) {
            chunks.push(rows.slice(i, i + size));
        }
        return chunks;
    }

    handleClose() {
        this.close(this.hasImported ? 'imported' : 'cancelled');
    }

    parseCsv(text) {
        const rows = [];
        let row = [];
        let field = '';
        let inQuotes = false;

        for (let i = 0; i < text.length; i++) {
            const char = text[i];
            if (inQuotes) {
                if (char === '"') {
                    if (text[i + 1] === '"') {
                        field += '"';
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    field += char;
                }
            } else if (char === '"') {
                inQuotes = true;
            } else if (char === ',') {
                row.push(field);
                field = '';
            } else if (char === '\n' || char === '\r') {
                if (char === '\r' && text[i + 1] === '\n') {
                    i++;
                }
                row.push(field);
                rows.push(row);
                row = [];
                field = '';
            } else {
                field += char;
            }
        }
        if (field.length > 0 || row.length > 0) {
            row.push(field);
            rows.push(row);
        }
        return rows.filter((r) => r.some((cell) => cell.trim() !== ''));
    }

    buildImportRows(csvRows) {
        const [headerRow, ...dataRows] = csvRows;
        const columnKeys = headerRow.map((header) => HEADER_MAP[header.trim().toLowerCase()] || null);

        return dataRows.map((dataRow) => {
            const record = {};
            columnKeys.forEach((key, idx) => {
                if (!key) {
                    return;
                }
                const raw = (dataRow[idx] || '').trim();
                record[key] = DATE_FIELDS.has(key) ? this.parseDateToIso(raw) : raw || null;
            });
            return record;
        });
    }

    parseDateToIso(value) {
        if (!value) {
            return null;
        }
        const parts = value.split('/');
        if (parts.length !== 3) {
            return null;
        }
        const [month, day, year] = parts.map((p) => p.trim());
        if (!month || !day || !year) {
            return null;
        }
        return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
    }
}
