import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import AddReviewModal from 'c/addReviewModal';

export default class AdmissionDetailModal extends LightningModal {
    @api recordId;

    handleClose() {
        this.close('closed');
    }

    async handleAddReview() {
        const result = await AddReviewModal.open({
            size: 'large',
            admissionId: this.recordId
        });
        if (result === 'saved') {
            this.close('addReview');
        }
    }
}
