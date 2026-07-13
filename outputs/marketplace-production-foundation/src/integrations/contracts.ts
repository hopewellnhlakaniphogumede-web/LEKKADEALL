export type Money = { amountMinor: number; currency: 'ZAR' };
export type ProviderName = 'mock' | 'tradesafe' | 'netcash' | 'verifynow' | 'iidentifii' | 'clickatell';
export type PaymentProviderMode = 'mock' | 'sandbox' | 'live';
export type MockPaymentOutcomeStatus = 'paid' | 'failed';

export type PaymentStatus =
  | 'pending'
  | 'checkout_created'
  | 'paid'
  | 'failed'
  | 'expired'
  | 'cancelled'
  | 'partially_refunded'
  | 'refunded';

export type ReleaseStatus =
  | 'not_applicable'
  | 'pending'
  | 'paused'
  | 'eligible'
  | 'released'
  | 'cancelled';

export type PaymentMethod =
  | 'platform_online_pending'
  | 'platform_online'
  | 'sandbox_online'
  | 'manual_sandbox_online';

export interface CreateProtectedPaymentInput {
  idempotencyKey: string;
  bookingId: string;
  customerId: string;
  providerId: string;
  serviceAmount: Money;
  platformFee: Money;
  returnUrl: string;
  cancelUrl: string;
  description: string;
}

export interface HostedCheckoutSessionInput {
  paymentId: string;
  idempotencyKey: string;
  returnUrl: string;
  cancelUrl: string;
}

export interface HostedCheckoutSession {
  paymentId: string;
  provider: Extract<ProviderName, 'mock'>;
  providerReference: string;
  checkoutUrl: string;
  status: Extract<PaymentStatus, 'checkout_created'>;
  expiresAt: string;
  realMoneyMoved: false;
}

export interface MockPaymentOutcomeInput {
  paymentId: string;
  outcomeStatus: MockPaymentOutcomeStatus;
  providerEventId: string;
  idempotencyKey: string;
  reason: string;
  metadata?: Record<string, unknown>;
}

export interface ProtectedPayment {
  provider: ProviderName;
  providerReference: string;
  checkoutUrl: string;
  status: PaymentStatus;
  paymentMethod?: PaymentMethod;
  releaseStatus?: ReleaseStatus;
  expiresAt?: string;
}

export interface RefundInput {
  idempotencyKey: string;
  paymentReference: string;
  amount: Money;
  reasonCode: string;
  internalCaseId?: string;
}

export interface PaymentWebhookEvent {
  provider: ProviderName;
  eventId: string;
  eventType: string;
  providerReference: string;
  occurredAt: string;
  status: PaymentStatus;
  rawPayloadHash: string;
}

export type MockPaymentWebhookEventType =
  | 'mock.checkout.created'
  | 'mock.payment.paid'
  | 'mock.payment.failed'
  | 'mock.payment.expired'
  | 'mock.payment.cancelled';

export interface VerifiedPaymentWebhookEnvelope {
  provider: Extract<ProviderName, 'mock'>;
  providerEventId: string;
  providerReference: string;
  eventType: MockPaymentWebhookEventType;
  payloadHash: string;
  idempotencyKey: string;
  safeMetadata: Record<string, unknown>;
}

export interface PaymentWebhookRouteConfig {
  appEnv: 'local' | 'development' | 'dev' | 'test' | 'ci' | 'sandbox' | 'production' | 'prod';
  providerMode: PaymentProviderMode;
  webhookToleranceSeconds: number;
  // Secret values are server-runtime configuration only and must never be sent to clients.
  webhookSecretPresent: boolean;
}

export interface PaymentGateway {
  createProtectedPayment(input: CreateProtectedPaymentInput): Promise<ProtectedPayment>;
  getPayment(providerReference: string): Promise<ProtectedPayment>;
  pauseRelease(providerReference: string, caseId: string): Promise<void>;
  release(providerReference: string, idempotencyKey: string): Promise<void>;
  refund(input: RefundInput): Promise<{ providerRefundReference: string; status: PaymentStatus }>;
  verifyAndParseWebhook(rawBody: Uint8Array, signature: string): Promise<PaymentWebhookEvent>;
}

export type VerificationStatus = 'not_started' | 'pending' | 'verified' | 'manual_review' | 'rejected' | 'expired';

export interface StartVerificationInput {
  userId: string;
  correlationId: string;
  country: 'ZA';
  callbackUrl: string;
  returnUrl: string;
  checks: Array<'document' | 'identity_source' | 'face_match' | 'liveness' | 'bank_account_name'>;
  consentRecordedAt: string;
  consentVersion: string;
}

export interface VerificationSession {
  provider: ProviderName;
  providerReference: string;
  hostedUrl?: string;
  sdkToken?: string;
  status: VerificationStatus;
  expiresAt: string;
}

export interface VerificationResult {
  provider: ProviderName;
  providerReference: string;
  status: VerificationStatus;
  assuranceLevel?: string;
  failureCodes: string[];
  completedAt?: string;
  // Never include raw document images or biometric templates here.
  verifiedAttributes?: { idCountry?: 'ZA'; nameMatch?: boolean; bankNameMatch?: boolean };
}

export interface IdentityGateway {
  start(input: StartVerificationInput): Promise<VerificationSession>;
  getResult(providerReference: string): Promise<VerificationResult>;
  requestDeletion(providerReference: string): Promise<{ accepted: boolean; reference: string }>;
  verifyWebhook(rawBody: Uint8Array, signature: string): Promise<{ eventId: string; providerReference: string; status: VerificationStatus }>;
}

export type MessagePurpose = 'otp' | 'booking' | 'bid' | 'payment' | 'dispute' | 'security' | 'marketing';

export interface SendMessageInput {
  idempotencyKey: string;
  recipient: string;
  templateId: string;
  purpose: MessagePurpose;
  variables: Record<string, string>;
  preferredChannel: 'sms' | 'whatsapp' | 'email';
  fallbackChannels?: Array<'sms' | 'whatsapp' | 'email'>;
  consentReference?: string;
}

export interface MessagingGateway {
  send(input: SendMessageInput): Promise<{ providerReference: string; acceptedChannel: string }>;
  getDelivery(providerReference: string): Promise<{ status: 'queued' | 'sent' | 'delivered' | 'failed'; occurredAt: string }>;
  verifyWebhook(rawBody: Uint8Array, signature: string): Promise<{ eventId: string; providerReference: string; status: string }>;
}

export interface VendorRegistry {
  payments: PaymentGateway;
  identity: IdentityGateway;
  messaging: MessagingGateway;
}
