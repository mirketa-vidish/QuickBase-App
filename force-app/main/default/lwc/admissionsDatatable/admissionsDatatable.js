import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import getAdmissions from '@salesforce/apex/AdmissionDatatableController.getAdmissions';
import ReviewsListModal from 'c/reviewsListModal';
import AddReviewModal from 'c/addReviewModal';

const PAGE_SIZE_OPTIONS = [10, 25, 50, 100].map((n) => ({ label: String(n), value: String(n) }));
const FILTER_DEBOUNCE_MS = 400;
const RT_ADMISSION_REVIEW = 'Admission_Review';
const RT_ONGOING_REVIEW = 'Ongoing_Review';

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

    openReviewsList(recordId, reviewType, modalTitle) {
        return ReviewsListModal.open({
            size: 'large',
            admissionId: recordId,
            reviewType,
            modalTitle
        });
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