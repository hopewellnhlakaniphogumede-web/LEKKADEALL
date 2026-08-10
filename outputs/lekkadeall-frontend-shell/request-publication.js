import { isCustomerRequestId } from './customer-requests.js';

export const CUSTOMER_PUBLISH_DRAFT_RPC = 'customer_publish_draft_request';
export const DRAFT_PUBLICATION_CONFIRM_TITLE = 'Publish this request?';
export const DRAFT_PUBLICATION_CONFIRM_TEXT = 'The reviewed request fields will become visible in the marketplace after server confirmation.';
export const DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE = 'This draft is not available for publication.';
export const DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE = 'Publication could not be confirmed. Refresh the request before making another change.';
export const DRAFT_PUBLICATION_SUCCESS_MESSAGE = 'Request published.';

export async function publishCustomerDraft(client, requestId) {
  if (!client || !isCustomerRequestId(requestId)) {
    return {
      ok: false,
      kind: 'unavailable',
      message: DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE,
    };
  }

  try {
    const { data, error } = await client.rpc('customer_publish_draft_request', {
      p_request_id: requestId,
    });

    if (error) {
      const kind = ['22023', '42501'].includes(error.code) ? 'unavailable' : 'ambiguous';
      return {
        ok: false,
        kind,
        message: kind === 'unavailable'
          ? DRAFT_PUBLICATION_UNAVAILABLE_MESSAGE
          : DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE,
      };
    }

    if (data !== 'open') {
      return {
        ok: false,
        kind: 'ambiguous',
        message: DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE,
      };
    }

    return { ok: true, status: 'open' };
  } catch {
    return {
      ok: false,
      kind: 'ambiguous',
      message: DRAFT_PUBLICATION_AMBIGUOUS_MESSAGE,
    };
  }
}
