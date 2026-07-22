import { isCustomerRequestId } from './customer-requests.js';

export const CUSTOMER_UPDATE_DRAFT_RPC = 'customer_update_draft_request';
export const DRAFT_EDIT_UNAVAILABLE_MESSAGE = 'This draft is not available for editing.';
export const DRAFT_EDIT_AMBIGUOUS_MESSAGE = 'The update could not be confirmed. Refresh the draft before trying again.';
export const DRAFT_EDIT_SUCCESS_MESSAGE = 'Draft updated.';

function requestedStartToSastInput(value) {
  const parsed = new Date(value);
  if (!value || !Number.isFinite(parsed.getTime())) return '';
  const sastMilliseconds = parsed.getTime() + (2 * 60 * 60 * 1000);
  return new Date(sastMilliseconds).toISOString().slice(0, 16);
}

function budgetMinorToZarInput(value) {
  if (value === null || value === undefined) return '';
  if (!Number.isSafeInteger(value) || value < 0) return '';
  const minor = BigInt(value);
  return `${minor / 100n}.${(minor % 100n).toString().padStart(2, '0')}`;
}

export function customerDraftToEditValues(request) {
  if (!request || !isCustomerRequestId(request.id) || request.status !== 'draft') return null;
  return {
    category: String(request.category_id ?? ''),
    title: String(request.title ?? ''),
    description: String(request.description ?? ''),
    suburb: String(request.suburb ?? ''),
    city: String(request.city ?? ''),
    requestedStart: requestedStartToSastInput(request.requested_start),
    budget: budgetMinorToZarInput(request.budget_minor),
  };
}

export async function updateCustomerDraft(client, requestId, validatedValues) {
  if (!client || !isCustomerRequestId(requestId)) {
    return { ok: false, kind: 'unavailable', message: DRAFT_EDIT_UNAVAILABLE_MESSAGE };
  }

  const payload = {
    p_request_id: requestId,
    p_category_id: validatedValues.categoryId,
    p_title: validatedValues.title,
    p_description: validatedValues.description,
    p_suburb: validatedValues.suburb,
    p_city: validatedValues.city,
    p_requested_start: validatedValues.requestedStart,
    p_budget_minor: validatedValues.budgetMinor,
  };

  try {
    const { data, error } = await client.rpc(CUSTOMER_UPDATE_DRAFT_RPC, payload);
    if (error) {
      const kind = ['22023', '42501'].includes(error.code) ? 'unavailable' : 'ambiguous';
      return {
        ok: false,
        kind,
        message: kind === 'unavailable' ? DRAFT_EDIT_UNAVAILABLE_MESSAGE : DRAFT_EDIT_AMBIGUOUS_MESSAGE,
      };
    }
    if (data !== requestId) {
      return { ok: false, kind: 'ambiguous', message: DRAFT_EDIT_AMBIGUOUS_MESSAGE };
    }
    return { ok: true, requestId: data };
  } catch {
    return { ok: false, kind: 'ambiguous', message: DRAFT_EDIT_AMBIGUOUS_MESSAGE };
  }
}
