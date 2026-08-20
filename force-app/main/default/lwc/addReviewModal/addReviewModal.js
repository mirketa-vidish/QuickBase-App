import { api, wire } from 'lwc';
import LightningModal from 'lightning/modal';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { updateRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const REVIEW_OBJECT_API_NAME = 'Review__c';
// The Review->Admission (Opportunity) lookup. Set on the new record after
// creation (rather than relying on it being an editable field on the page
// layout) so it's always correctly linked to the row Add Review was clicked
// from, regardless of which fields that Record Type's layout happens to show.
const ADMISSION_LOOKUP_FIELD = 'Opportunity__c';

export default class AddReviewModal extends LightningModal {
    @api admissionId;

    // Confirmed selection - drives whether the form step is shown.
    selectedRecordTypeId;
    // In-progress radio selection on the record-type step, before Next.
    pendingRecordTypeId;

    @wire(getObjectInfo, { objectApiName: REVIEW_OBJECT_API_NAME })
    objectInfo;

    get isSelectingType() {
        return !this.selectedRecordTypeId;
    }

    get recordTypeOptions() {
        const info = this.objectInfo?.data;
        if (!info) {
            return [];
        }
        return Object.values(info.recordTypeInfos)
            .filter((rt) => rt.available && !rt.master)
            .map((rt) => ({ label: rt.name, value: rt.recordTypeId }));
    }

    get hasNoRecordTypes() {
        return !!this.objectInfo?.data && this.recordTypeOptions.length === 0;
    }

    get isNextDisabled() {
        return !this.pendingRecordTypeId;
    }

    handleRecordTypeChange(event) {
        this.pendingRecordTypeId = event.detail.value;
    }

    handleNext() {
        if (this.pendingRecordTypeId) {
            this.selectedRecordTypeId = this.pendingRecordTypeId;
        }
    }

    handleCancel() {
        this.close('cancelled');
    }

    async handleFormSuccess(event) {
        const newReviewId = event.detail.id;
        try {
            await updateRecord({
                fields: {
                    Id: newReviewId,
                    [ADMISSION_LOOKUP_FIELD]: this.admissionId
                }
            });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Review saved.',
                    variant: 'success'
                })
            );
        } catch (error) {
            // The review record itself was already created successfully -
            // surface the link failure as a warning rather than losing the
            // user's saved data.
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Review saved, but linking to the Admission failed',
                    message: error?.body?.message || 'Please open the review and set the Admission manually.',
                    variant: 'warning'
                })
            );
        }
        this.close('saved');
    }
}
