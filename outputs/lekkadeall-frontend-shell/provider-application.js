import { containsRequestPrivacyRisk } from './request-draft.js';

export const CUSTOMER_PROVIDER_APPLICATION_RPC = 'customer_submit_provider_application';
export const PROVIDER_APPLICATION_TERMS_VERSION = 'provider-application-v1';
export const PROVIDER_APPLICATION_CONFIRM_TITLE = 'Submit provider application?';
export const PROVIDER_APPLICATION_CONFIRM_TEXT = 'Your application will remain pending and unverified until a separate controlled review is completed.';
export const PROVIDER_APPLICATION_UNAVAILABLE_MESSAGE = 'Provider application is unavailable.';
export const PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE = 'The application could not be confirmed. Refresh your account before trying again.';
export const PROVIDER_APPLICATION_SUCCESS_MESSAGE = 'Provider application submitted. Your status is pending and unverified.';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const CONTROL_PATTERN = /[\u0000-\u001f\u007f]/u;

export function validateProviderApplication(values, activeCategories) {
  const errors = {};
  const businessName = String(values?.businessName ?? '').trim();
  const businessNameLength = Array.from(businessName).length;
  if (businessNameLength < 3 || businessNameLength > 120) {
    errors.businessName = 'Business name must be between 3 and 120 characters.';
  } else if (CONTROL_PATTERN.test(businessName) || containsRequestPrivacyRisk(businessName)) {
    errors.businessName = 'Business name contains unsupported or private information.';
  }

  const radiusText = String(values?.serviceRadiusKm ?? '').trim();
  const serviceRadiusKm = /^\d{1,3}$/u.test(radiusText) ? Number(radiusText) : null;
  if (!Number.isInteger(serviceRadiusKm) || serviceRadiusKm < 1 || serviceRadiusKm > 250) {
    errors.serviceRadiusKm = 'Service radius must be a whole number from 1 to 250 kilometres.';
  }

  const allowedCategoryIds = new Set(
    Array.isArray(activeCategories)
      ? activeCategories.map((category) => category?.id).filter((id) => UUID_PATTERN.test(String(id ?? '')))
      : [],
  );
  const categoryIds = Array.isArray(values?.categoryIds)
    ? [...new Set(values.categoryIds.map((value) => String(value)))]
    : [];
  if (categoryIds.length < 1 || categoryIds.length > 10
      || categoryIds.some((categoryId) => !UUID_PATTERN.test(categoryId)
        || !allowedCategoryIds.has(categoryId))) {
    errors.categoryIds = 'Choose between one and ten available service categories.';
  }

  if (values?.acceptedTerms !== true) {
    errors.acceptedTerms = 'Accept the provider application terms before continuing.';
  }

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    values: {
      businessName,
      serviceRadiusKm,
      categoryIds,
      termsVersion: PROVIDER_APPLICATION_TERMS_VERSION,
    },
  };
}

export async function submitCustomerProviderApplication(client, validatedValues) {
  if (!client || !validatedValues || validatedValues.termsVersion !== PROVIDER_APPLICATION_TERMS_VERSION) {
    return { ok: false, kind: 'unavailable', message: PROVIDER_APPLICATION_UNAVAILABLE_MESSAGE };
  }

  const payload = {
    p_business_name: validatedValues.businessName,
    p_service_radius_km: validatedValues.serviceRadiusKm,
    p_category_ids: validatedValues.categoryIds,
    p_terms_version: PROVIDER_APPLICATION_TERMS_VERSION,
  };

  try {
    const { data, error } = await client.rpc(CUSTOMER_PROVIDER_APPLICATION_RPC, payload);
    if (error) {
      const kind = typeof error.code === 'string' && !error.code.startsWith('08')
        ? 'unavailable'
        : 'ambiguous';
      return {
        ok: false,
        kind,
        message: kind === 'unavailable'
          ? PROVIDER_APPLICATION_UNAVAILABLE_MESSAGE
          : PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE,
      };
    }
    if (data !== 'pending') {
      return { ok: false, kind: 'ambiguous', message: PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE };
    }
    return { ok: true, status: 'pending' };
  } catch {
    return { ok: false, kind: 'ambiguous', message: PROVIDER_APPLICATION_AMBIGUOUS_MESSAGE };
  }
}

export function isEligibleCustomerProviderApplication(
  profile,
  providerResult,
  requestResult,
  bookingResult,
  activeCategories,
) {
  return profile?.role === 'customer'
    && profile.account_status === 'active'
    && providerResult?.ok === true
    && providerResult.data === null
    && requestResult?.ok === true
    && Array.isArray(requestResult.data)
    && requestResult.data.length === 0
    && bookingResult?.ok === true
    && Array.isArray(bookingResult.data)
    && bookingResult.data.length === 0
    && Array.isArray(activeCategories)
    && activeCategories.length > 0;
}

export function isConfirmedPendingProviderApplication(actorId, profileResult, providerResult) {
  const profile = profileResult?.ok ? profileResult.data : null;
  const provider = providerResult?.ok ? providerResult.data : null;
  return typeof actorId === 'string'
    && profile?.id === actorId
    && profile.role === 'provider'
    && profile.account_status === 'active'
    && provider?.user_id === actorId
    && provider.verification_status === 'not_started'
    && provider.review_status === 'pending';
}
