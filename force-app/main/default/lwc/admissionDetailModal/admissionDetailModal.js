import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';

export default class AdmissionDetailModal extends NavigationMixin(LightningModal) {
    @api recordId;

    handleClose() {
        this.close('closed');
    }

    handleAddReview() {
        // No recordTypeId is passed, so Salesforce shows its standard
        // record-type selection screen for Review__c, same as the datatable's
        // own Add Review action.
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Review__c',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: encodeDefaultFieldValues({ Admission__c: this.recordId })
            }
        });
        this.close('addReview');
    }
}