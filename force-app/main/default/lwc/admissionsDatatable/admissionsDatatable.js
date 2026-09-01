import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getAdmissions from '@salesforce/apex/AdmissionDatatableController.getAdmissions';
import exportAdmissions from '@salesforce/apex/AdmissionDatatableController.exportAdmissions';
import ReviewsListModal from 'c/reviewsListModal';
import AddReviewModal from 'c/addReviewModal';

const PAGE_SIZE_OPTIONS = [10, 25, 50, 100].map((n) => ({ label: String(n), value: String(n) }));
const FILTER_DEBOUNCE_MS = 400;
const RT_ADMISSION_REVIEW = 'Admission_Review';
const RT_ONGOING_REVIEW = 'Ongoing_Review';
const EXPORT_COLUMNS = [
    { label: 'Admission ID', field: 'admissionId' },
    { label: 'MBC ID', field: 'mbcId' },
    { label: 'Admission Date', field: 'admissionDate' },
    { label: 'Discharge Date', field: 'dischargeDate' },
    { label: 'Status', field: 'status' },
    { label: 'Patient Name', field: 'patientName' },
    { label: 'Program', field: 'program' },
    { label: 'Current Service Facility', field: 'currentServiceFacility' },
    { label: 'Current Level Of Care', field: 'currentLevelOfCare' },
    { label: 'Realm', field: 'realm' },
    { label: 'Primary Counselor', field: 'primaryCounselor' },
    { label: 'Combined Text Supervisor', field: 'combinedTextSupervisor' },
    { label: 'MRI', field: 'mri' },
    { label: '# of Admission Reviews', field: 'admissionReviewCount' },
    { label: '# of Ongoing Reviews', field: 'ongoingReviewCount' },
    { label: '# of All Reviews', field: 'allReviewCount' }
];

export default class AdmissionsDatatable extends NavigationMixin(LightningElement) {
    records = [];
    totalRecords = 0;
    pageNumber = 1;
    pageSize = 25;
    sortField = 'admissionDate';
    sortDirection = 'desc';
    showFilters = false;
    filters = {};
    isLoading = false;
    isExporting = false;
    errorMessage;

    pageSizeOptions = PAGE_SIZE_OPTIONS;
    filterTimeoutId;

    // Lightning often keeps this component's instance alive rather than
    // fully remounting it when the user navigates away (e.g. to create a
    // Review) and back - so connectedCallback's one-time load wouldn't pick
    // up newly created records. CurrentPageReference re-fires every time
    // navigation returns to this view, so it doubles as a "refresh on
    // return" hook (as well as the initial load).
    @wire(CurrentPageReference)
    handlePageReferenceChange(pageReference) {
        if (pageReference) {
            this.loadData();
        }
    }

    async loadData() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const result = await getAdmissions({
                filters: this.filters,
                sortField: this.sortField,
                sortDirection: this.sortDirection,
                pageNumber: this.pageNumber,
                pageSize: this.pageSize
            });
            this.records = result.records;
            this.totalRecords = result.totalRecords;
        } catch (error) {
            this.errorMessage = error?.body?.message || 'Failed to load admissions.';
            this.records = [];
            this.totalRecords = 0;
        } finally {
            this.isLoading = false;
        }
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
    }

    get isFirstPage() {
        return this.pageNumber <= 1;
    }

    get isLastPage() {
        return this.pageNumber >= this.totalPages;
    }

    get pageInfoLabel() {
        return `Page ${this.pageNumber} of ${this.totalPages} (${this.totalRecords} records)`;
    }

    get pageSizeValue() {
        return String(this.pageSize);
    }

    get filterIconVariant() {
        return this.showFilters ? 'brand' : 'border-filled';
    }

    get hasNoRecords() {
        return !this.isLoading && this.records.length === 0;
    }

    toggleFilters() {
        this.showFilters = !this.showFilters;
    }

    handleRefreshClick() {
        this.loadData();
    }

    async handleExportClick() {
        this.isExporting = true;
        this.errorMessage = undefined;
        try {
            const rows = await exportAdmissions({
                filters: this.filters,
                sortField: this.sortField,
                sortDirection: this.sortDirection
            });
            this.downloadCsv(this.buildCsv(rows), 'admissions_export.csv');
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('[admissionsDatatable] export failed', error);
            this.errorMessage = error?.body?.message || error?.message || 'Failed to export admissions.';
        } finally {
            this.isExporting = false;
        }
    }

    buildCsv(rows) {
        const lines = [EXPORT_COLUMNS.map((col) => this.csvEscape(col.label)).join(',')];
        rows.forEach((row) => {
            lines.push(EXPORT_COLUMNS.map((col) => this.csvEscape(row[col.field])).join(','));
        });
        return lines.join('\r\n');
    }

    csvEscape(value) {
        if (value === null || value === undefined) {
            return '';
        }
        const str = String(value);
        return /[",\r\n]/.test(str) ? `"${str.replace(/"/g, '""')}"` : str;
    }

    downloadCsv(csvContent, fileName) {
        // Lightning Web Security validates Blob MIME types against an
        // allowlist that excludes 'text/csv' entirely (with or without a
        // charset parameter). 'text/plain' is accepted, and the saved
        // file's association still comes from the .csv filename extension
        // on the download link below, not this MIME type.
        const bom = String.fromCharCode(0xfeff);
        const blob = new Blob([bom + csvContent], { type: 'text/plain' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = fileName;
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(url);
    }

    handleFilterInput(event) {
        const field = event.target.dataset.filter;
        const value = event.target.value;
        this.filters = { ...this.filters, [field]: value };

        window.clearTimeout(this.filterTimeoutId);
        this.filterTimeoutId = window.setTimeout(() => {
            this.pageNumber = 1;
            this.loadData();
        }, FILTER_DEBOUNCE_MS);
    }

    clearFilters() {
        window.clearTimeout(this.filterTimeoutId);
        this.filters = {};
        this.pageNumber = 1;
        this.loadData();
    }

    handleSort(event) {
        const field = event.currentTarget.dataset.field;
        if (this.sortField === field) {
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            this.sortField = field;
            this.sortDirection = 'asc';
        }
        this.loadData();
    }

    handlePrevious() {
        if (!this.isFirstPage) {
            this.pageNumber -= 1;
            this.loadData();
        }
    }

    handleNext() {
        if (!this.isLastPage) {
            this.pageNumber += 1;
            this.loadData();
        }
    }

    handlePageSizeChange(event) {
        this.pageSize = Number(event.detail.value);
        this.pageNumber = 1;
        this.loadData();
    }

    handleEditClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Opportunity',
                actionName: 'edit'
            }
        });
    }

    handleViewClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Opportunity',
                actionName: 'view'
            }
        });
    }

    async handleAddReviewClick(event) {
        const recordId = event.currentTarget.dataset.id;
        const result = await AddReviewModal.open({
            size: 'large',
            admissionId: recordId
        });
        if (result === 'saved') {
            this.loadData();
        }
    }

    async openReviewsList(recordId, reviewType, modalTitle) {
        const result = await ReviewsListModal.open({
            size: 'large',
            admissionId: recordId,
            reviewType,
            modalTitle
        });
        // The modal can't reliably use NavigationMixin itself (its content
        // renders into a separate DOM branch), so it reports back what the
        // user wants to do and this component - a normal part of the page
        // tree - performs the actual navigation once the modal is closed.
        if (result?.action === 'navigate') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: result.recordId,
                    objectApiName: result.objectApiName,
                    actionName: result.actionName
                }
            });
        }
    }

    handleReviewsLinkClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this.openReviewsList(recordId, null, 'Reviews');
    }

    handleAdmissionCountClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this.openReviewsList(recordId, RT_ADMISSION_REVIEW, 'Admission Reviews');
    }

    handleOngoingCountClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this.openReviewsList(recordId, RT_ONGOING_REVIEW, 'Ongoing Reviews');
    }

    handleAllCountClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this.openReviewsList(recordId, null, 'All Reviews');
    }
}