import { getEnv } from '@/config/env';
import { mockProviders } from './mocks';
import type { Providers } from './types';

export * from './types';

/**
 * §46 — the single place a concrete provider is chosen. Business logic imports
 * getProviders(), never a vendor SDK.
 *
 * Every slot is a mock in M0. Each becomes real at the milestone that implements
 * it (storage M7, payment M8, domain M3, whatsapp/sms/email M10), and the mock
 * remains the test double.
 */
export function getProviders(): Providers {
  getEnv(); // fail fast on misconfiguration before any provider is handed out
  return mockProviders;
}
