import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { NavigationMixin } from 'lightning/navigation';
import getReviews from '@salesforce/apex/ReviewListController.getReviews';

const DEFAULT_PAGE_SIZE = 25;

export default class ReviewsListModal extends NavigationMixin(LightningModal) {
    @api admissionId;
    @api reviewType;
    @api modalTitle = 'Reviews';

    records = [];
    totalRecords = 0;
    pageNumber = 1;
    pageSize = DEFAULT_PAGE_SIZE;
    isLoading = false;
    errorMessage;

    connectedCallback() {
        this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const result = await getReviews({
                admissionId: this.admissionId,
                reviewType: this.reviewType,
                pageNumber: this.pageNumber,
                pageSize: this.pageSize
            });
            this.records = result.records;
            this.totalRecords = result.totalRecords;
        } catch (error) {
            this.errorMessage = error?.body?.message || 'Failed to load reviews.';
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

    get hasNoRecords() {
        return !this.isLoading && this.records.length === 0;
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

    handleRowClick(event) {
        const recordId = event.currentTarget.dataset.id;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Review__c',
                actionName: 'view'
            }
        });
    }

    handleClose() {
        this.close('closed');
    }
}