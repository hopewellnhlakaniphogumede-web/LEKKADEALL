import { isCustomerRequestId } from './customer-requests.js';

export const CUSTOMER_CANCEL_DRAFT_RPC = 'customer_cancel_draft_request';
export const DRAFT_CANCELLATION_CONFIRM_TITLE = 'Cancel this draft?';
export const DRAFT_CANCELLATION_CONFIRM_TEXT = 'This will mark the draft as cancelled. It will not publish the request or contact providers.';
export const DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE = 'This draft is not available for cancellation.';
export const DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE = 'Cancellation could not be confirmed. Refresh your requests before trying again.';
export const DRAFT_CANCELLATION_SUCCESS_MESSAGE = 'Draft cancelled.';

export async function cancelCustomerDraft(client, requestId) {
  if (!client || !isCustomerRequestId(requestId)) {
    return {
      ok: false,
      kind: 'unavailable',
      message: DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE,
    };
  }

  try {
    const { data, error } = await client.rpc(CUSTOMER_CANCEL_DRAFT_RPC, {
      p_request_id: requestId,
    });

    if (error) {
      const kind = ['22023', '42501'].includes(error.code) ? 'unavailable' : 'ambiguous';
      return {
        ok: false,
        kind,
        message: kind === 'unavailable'
          ? DRAFT_CANCELLATION_UNAVAILABLE_MESSAGE
          : DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE,
      };
    }

    if (data !== 'cancelled') {
      return {
        ok: false,
        kind: 'ambiguous',
        message: DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE,
      };
    }

    return { ok: true, status: 'cancelled' };
  } catch {
    return {
      ok: false,
      kind: 'ambiguous',
      message: DRAFT_CANCELLATION_AMBIGUOUS_MESSAGE,
    };
  }
}
