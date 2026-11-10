import { SUPPORT_EMAIL, supportMailto } from '@/lib/public-config';

/* Where to reach the developer directly. Shared by the footer and the About
   page, so the two can never disagree. */
export const contacts = [
  {
    service: 'instagram',
    icon: '/social-icons/instagram.svg',
    label: 'Instagram',
    value: '@r.bondeth',
    href: 'https://www.instagram.com/r.bondeth/',
  },
  {
    service: 'telegram',
    icon: '/social-icons/telegram.svg',
    label: 'Telegram',
    value: '@hemrithybondeth',
    href: 'https://t.me/hemrithybondeth',
  },
  {
    service: 'whatsapp',
    icon: '/social-icons/whatsapp.svg',
    label: 'WhatsApp',
    value: '+855 85 872 582',
    href: 'https://wa.me/85585872582',
  },
  {
    service: 'email',
    icon: '/social-icons/gmail.svg',
    label: 'Email',
    value: SUPPORT_EMAIL,
    href: supportMailto('Question about Bondex Notch'),
  },
];

export const GITHUB_PROFILE_URL = 'https://github.com/RithyBondeth';
