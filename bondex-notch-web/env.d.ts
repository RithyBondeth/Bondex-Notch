export {};

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NEXT_PUBLIC_SITE_URL?: string;
      NEXT_PUBLIC_SUPPORT_EMAIL?: string;
    }
  }
}
