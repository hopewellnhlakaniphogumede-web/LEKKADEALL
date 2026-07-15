export const CUSTOMER_CREATE_DRAFT_RPC = 'customer_create_draft_request';

export const REQUEST_PRIVACY_WARNING = 'This title and description may later be shown to service providers. Do not include your exact address, street or house number, complex, unit or room number, GPS location, phone number, email address, access code, or private contact details. Enter suburb and city only.';

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SINGLE_LINE_CONTROL_PATTERN = /[\u0000-\u001f\u007f]/u;
const DESCRIPTION_CONTROL_PATTERN = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u;
const PRIVACY_RISK_PATTERNS = Object.freeze([
  /(^|[^\p{L}\p{N}])\d{1,5}\s+[\p{L}][\p{L}\p{N} .'-]{1,80}\s+(street|st|road|rd|avenue|ave|drive|dr|lane|ln|way|close|crescent|cres|boulevard|blvd|place|pl|terrace|terr)([^\p{L}\p{N}]|$)/iu,
  /(^|[^\p{L}\p{N}])(unit|flat|room|apt|apartment|suite)\s*(?:(no\.?|number|#)\s*[\p{L}\p{N}-]{1,10}|[\p{L}]{0,2}\d[\p{L}\p{N}-]*|[\p{L}])([^\p{L}\p{N}]|$)/iu,
  /(^|[^\p{L}\p{N}])(house|stand|erf)\s*(no\.?|number|#)?\s*\d{1,6}([^\p{L}\p{N}]|$)/iu,
  /[-+]?\d{1,2}\.\d{4,}\s*,\s*[-+]?\d{1,3}\.\d{4,}/u,
  /(^|\D)(\+27|0)\d(?:[\s-]*\d){8}(\D|$)/u,
  /[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}/iu,
  /\bhttps?:\/\/|\bwww\./iu,
  /\b(whats\s*app|telegram|contact\s+me|call\s+me|email\s+me|dm\s+me)\b/iu,
  /(^|\s)@[\p{L}\p{N}_]{2,}/iu,
  /\b(gate|access)\s*(code|pin)\b/iu,
]);

function textLength(value) {
  return Array.from(value).length;
}

export function containsRequestPrivacyRisk(value) {
  const text = String(value ?? '');
  return PRIVACY_RISK_PATTERNS.some((pattern) => pattern.test(text));
}

export function parseZarToMinorUnits(value) {
  const text = String(value ?? '');
  if (text === '') return { ok: true, value: null };
  if (!/^\d+(?:\.\d{1,2})?$/.test(text)) {
    return { ok: false, message: 'Enter a ZAR amount using digits and up to two decimal places.' };
  }

  const [major, fraction = ''] = text.split('.');
  const minor = (BigInt(major) * 100n) + BigInt(fraction.padEnd(2, '0'));
  if (minor > 2147483647n) {
    return { ok: false, message: 'The budget is above the supported maximum.' };
  }
  return { ok: true, value: Number(minor) };
}

export function sastDateTimeToIso(value, nowMs = Date.now(), minimumLeadMs = 15 * 60 * 1000) {
  const text = String(value ?? '');
  const match = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/.exec(text);
  if (!match) return { ok: false, message: 'Choose a valid date and time in SAST.' };

  const [, yearText, monthText, dayText, hourText, minuteText] = match;
  const year = Number(yearText);
  const month = Number(monthText);
  const day = Number(dayText);
  const hour = Number(hourText);
  const minute = Number(minuteText);
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  if (year < 2020 || month < 1 || month > 12 || day < 1 || day > daysInMonth || hour > 23 || minute > 59) {
    return { ok: false, message: 'Choose a valid date and time in SAST.' };
  }

  const iso = `${yearText}-${monthText}-${dayText}T${hourText}:${minuteText}:00+02:00`;
  const timestamp = Date.parse(iso);
  if (!Number.isFinite(timestamp) || timestamp < nowMs + minimumLeadMs) {
    return { ok: false, message: 'Choose a start time at least 15 minutes in the future.' };
  }
  return { ok: true, value: iso };
}

function validatePublicText(value, { field, minimum, maximum, multiline = false }) {
  const text = String(value ?? '').trim();
  const length = textLength(text);
  if (length < minimum || length > maximum) {
    return { ok: false, value: text, message: `${field} must be between ${minimum} and ${maximum} characters.` };
  }
  const invalidControl = multiline ? DESCRIPTION_CONTROL_PATTERN.test(text) : SINGLE_LINE_CONTROL_PATTERN.test(text);
  if (invalidControl) {
    return { ok: false, value: text, message: `${field} contains unsupported control characters.` };
  }
  if (containsRequestPrivacyRisk(text)) {
    return { ok: false, value: text, message: `${field} may contain private contact or exact-location details.` };
  }
  return { ok: true, value: text };
}

export function validateCustomerDraft(values, activeCategories, options = {}) {
  const errors = {};
  const categoryId = String(values.category ?? '');
  const categoryAllowed = UUID_PATTERN.test(categoryId)
    && Array.isArray(activeCategories)
    && activeCategories.some((category) => category.id === categoryId);
  if (!categoryAllowed) errors.category = 'Choose an available service category.';

  const title = validatePublicText(values.title, { field: 'Public title', minimum: 3, maximum: 120 });
  const description = validatePublicText(values.description, { field: 'Public description', minimum: 10, maximum: 3000, multiline: true });
  const suburb = validatePublicText(values.suburb, { field: 'Suburb', minimum: 2, maximum: 120 });
  const city = validatePublicText(values.city, { field: 'City', minimum: 2, maximum: 120 });
  if (!title.ok) errors.title = title.message;
  if (!description.ok) errors.description = description.message;
  if (!suburb.ok) errors.suburb = suburb.message;
  if (!city.ok) errors.city = city.message;

  const requestedStart = sastDateTimeToIso(values.requestedStart, options.nowMs, options.minimumLeadMs);
  if (!requestedStart.ok) errors.requestedStart = requestedStart.message;
  const budget = parseZarToMinorUnits(String(values.budget ?? ''));
  if (!budget.ok) errors.budget = budget.message;

  return {
    ok: Object.keys(errors).length === 0,
    errors,
    values: {
      categoryId,
      title: title.value,
      description: description.value,
      suburb: suburb.value,
      city: city.value,
      requestedStart: requestedStart.value ?? null,
      budgetMinor: budget.value ?? null,
    },
  };
}

export async function createCustomerDraftRequest(client, validatedValues) {
  const payload = {
    p_category_id: validatedValues.categoryId,
    p_title: validatedValues.title,
    p_description: validatedValues.description,
    p_suburb: validatedValues.suburb,
    p_city: validatedValues.city,
    p_requested_start: validatedValues.requestedStart,
    p_budget_minor: validatedValues.budgetMinor,
    p_precise_address_ciphertext: null,
  };
  const { data, error } = await client.rpc(CUSTOMER_CREATE_DRAFT_RPC, payload);
  if (error || typeof data !== 'string' || !UUID_PATTERN.test(data)) {
    return {
      ok: false,
      requestId: null,
      message: 'The draft could not be confirmed. Refresh your drafts before trying again.',
    };
  }
  return { ok: true, requestId: data };
}
