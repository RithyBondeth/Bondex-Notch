'use client';

import type { CSSProperties, FormEvent } from 'react';
import { useEffect, useId, useMemo, useState } from 'react';

export type CardState = {
  number: string;
  holder: string;
  month: string;
  year: string;
  cvv: string;
};

export type CardValidity = {
  number: boolean;
  holder: boolean;
  month: boolean;
  year: boolean;
  cvv: boolean;
  allValid: boolean;
};

type CreditCardFormProps = {
  defaultNumber?: string;
  defaultHolder?: string;
  defaultMonth?: string;
  defaultYear?: string;
  defaultCVV?: string;
  maskMiddle?: boolean;
  ring1?: string;
  ring2?: string;
  showSubmit?: boolean;
  submitLabel?: string;
  onChange?: (state: CardState, validity: CardValidity) => void;
  onSubmit?: (state: CardState, validity: CardValidity) => void;
  className?: string;
};

function formatNumberSpaces(number: string) {
  return number.replace(/\s+/g, '').replace(/(\d{4})(?=\d)/g, '$1 ');
}

function clampDigits(value: string, maxLength: number) {
  return value.replace(/\D/g, '').slice(0, maxLength);
}

function passesLuhn(number: string) {
  let sum = 0;
  let doubleDigit = false;

  for (let index = number.length - 1; index >= 0; index -= 1) {
    let digit = Number(number[index]);
    if (doubleDigit) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    doubleDigit = !doubleDigit;
  }

  return number.length >= 13 && sum % 10 === 0;
}

export function CreditCardForm({
  defaultNumber = '',
  defaultHolder = '',
  defaultMonth = '',
  defaultYear = '',
  defaultCVV = '',
  maskMiddle = true,
  ring1 = '#3cc1f6',
  ring2 = '#8d72ff',
  showSubmit = true,
  submitLabel = 'Review payment',
  onChange,
  onSubmit,
  className = '',
}: CreditCardFormProps) {
  const fieldPrefix = useId();
  const [number, setNumber] = useState(clampDigits(defaultNumber, 19));
  const [holder, setHolder] = useState(defaultHolder.toUpperCase());
  const [month, setMonth] = useState(defaultMonth);
  const [year, setYear] = useState(defaultYear);
  const [cvv, setCVV] = useState(clampDigits(defaultCVV, 4));
  const [focusField, setFocusField] = useState<
    null | 'number' | 'holder' | 'expire' | 'cvv'
  >(null);

  const years = useMemo(() => {
    const start = new Date().getFullYear();
    return Array.from({ length: 10 }, (_, index) => String(start + index));
  }, []);

  const validity = useMemo<CardValidity>(() => {
    const now = new Date();
    const selectedMonth = Number(month);
    const selectedYear = Number(year);
    const monthValid = selectedMonth >= 1 && selectedMonth <= 12;
    const yearValid =
      selectedYear > now.getFullYear() ||
      (selectedYear === now.getFullYear() && monthValid && selectedMonth >= now.getMonth() + 1);
    const numberValid = number.length <= 19 && passesLuhn(number);
    const holderValid = holder.trim().length >= 2;
    const cvvValid = /^\d{3,4}$/.test(cvv);

    return {
      number: numberValid,
      holder: holderValid,
      month: monthValid,
      year: yearValid,
      cvv: cvvValid,
      allValid: numberValid && holderValid && monthValid && yearValid && cvvValid,
    };
  }, [number, holder, month, year, cvv]);

  useEffect(() => {
    onChange?.({ number, holder, month, year, cvv }, validity);
  }, [number, holder, month, year, cvv, validity, onChange]);

  const displayedSlots = useMemo(() => {
    const digits = number.slice(0, 16).split('');
    return Array.from({ length: 16 }, (_, index) => {
      const hasValue = index < digits.length;
      const shouldMask = maskMiddle && index >= 4 && index <= 11;
      return {
        value: hasValue ? (shouldMask ? '•' : digits[index]) : '·',
        hasValue,
      };
    });
  }, [number, maskMiddle]);

  const cardStyle = {
    '--payment-ring-1': ring1,
    '--payment-ring-2': ring2,
  } as CSSProperties;

  const handleSubmit = (event: FormEvent) => {
    event.preventDefault();
    if (!validity.allValid) return;
    onSubmit?.({ number, holder, month, year, cvv }, validity);
  };

  return (
    <section className={`credit-card-form ${className}`.trim()}>
      <div className="payment-card-scene" aria-label="Live payment card preview">
        <div className={`payment-card${focusField === 'cvv' ? ' is-flipped' : ''}`}>
          <section className="payment-card__face payment-card__front" style={cardStyle}>
            <span className={`payment-card__highlight is-${focusField ?? 'hidden'}`} />
            <div className="payment-card__header">
              <span className="payment-card__brand">Bondex Pro</span>
              <span className="payment-card__network" aria-label="Card payment">
                <i />
                <i />
              </span>
            </div>

            <div className="payment-card__number" aria-label="Card number preview">
              {displayedSlots.map((slot, index) => (
                <span className={slot.hasValue ? 'has-value' : undefined} key={index}>
                  {slot.value}
                </span>
              ))}
            </div>

            <div className="payment-card__footer">
              <span>
                <small>Card holder</small>
                <strong>{holder || 'NAME ON CARD'}</strong>
              </span>
              <span>
                <small>Expires</small>
                <strong>{month || 'MM'}/{year ? year.slice(-2) : 'YY'}</strong>
              </span>
            </div>
          </section>

          <section className="payment-card__face payment-card__back" style={cardStyle}>
            <div className="payment-card__stripe" />
            <div className="payment-card__signature">
              <span>Authorized signature</span>
              <strong>{'•'.repeat(cvv.length) || 'CVV'}</strong>
            </div>
            <p>Bondex Notch · One-time Pro license</p>
          </section>
        </div>
      </div>

      <form className="payment-form" onSubmit={handleSubmit} noValidate>
        <div className="payment-field">
          <label htmlFor={`${fieldPrefix}-number`}>Card number</label>
          <input
            id={`${fieldPrefix}-number`}
            inputMode="numeric"
            autoComplete="cc-number"
            placeholder="1234 5678 9012 3456"
            value={formatNumberSpaces(number)}
            onChange={(event) => setNumber(clampDigits(event.target.value, 19))}
            onFocus={() => setFocusField('number')}
            onBlur={() => setFocusField(null)}
            aria-invalid={number.length >= 13 && !validity.number}
            aria-describedby={`${fieldPrefix}-number-hint`}
          />
          <small id={`${fieldPrefix}-number-hint`}>
            {number.length >= 13 && !validity.number
              ? 'Check the card number and try again.'
              : '13–19 digits. Spaces are added automatically.'}
          </small>
        </div>

        <div className="payment-field">
          <label htmlFor={`${fieldPrefix}-holder`}>Name on card</label>
          <input
            id={`${fieldPrefix}-holder`}
            type="text"
            autoComplete="cc-name"
            placeholder="JANE DOE"
            value={holder}
            onChange={(event) => setHolder(event.target.value.toUpperCase().slice(0, 32))}
            onFocus={() => setFocusField('holder')}
            onBlur={() => setFocusField(null)}
            aria-invalid={holder.length > 0 && !validity.holder}
          />
        </div>

        <div className="payment-field-row">
          <div className="payment-field">
            <label htmlFor={`${fieldPrefix}-month`}>Expiration date</label>
            <div className="payment-date-fields">
              <select
                id={`${fieldPrefix}-month`}
                value={month}
                onChange={(event) => setMonth(event.target.value)}
                onFocus={() => setFocusField('expire')}
                onBlur={() => setFocusField(null)}
                aria-label="Expiration month"
                aria-invalid={month.length > 0 && !validity.month}
              >
                <option value="" disabled>Month</option>
                {Array.from({ length: 12 }, (_, index) => String(index + 1).padStart(2, '0')).map(
                  (value) => <option value={value} key={value}>{value}</option>,
                )}
              </select>
              <select
                value={year}
                onChange={(event) => setYear(event.target.value)}
                onFocus={() => setFocusField('expire')}
                onBlur={() => setFocusField(null)}
                aria-label="Expiration year"
                aria-invalid={year.length > 0 && !validity.year}
              >
                <option value="" disabled>Year</option>
                {years.map((value) => <option value={value} key={value}>{value}</option>)}
              </select>
            </div>
          </div>

          <div className="payment-field">
            <label htmlFor={`${fieldPrefix}-cvv`}>Security code</label>
            <input
              id={`${fieldPrefix}-cvv`}
              inputMode="numeric"
              autoComplete="cc-csc"
              placeholder="123"
              value={cvv}
              onChange={(event) => setCVV(clampDigits(event.target.value, 4))}
              onFocus={() => setFocusField('cvv')}
              onBlur={() => setFocusField(null)}
              aria-invalid={cvv.length >= 3 && !validity.cvv}
            />
          </div>
        </div>

        {showSubmit && (
          <button className="payment-submit" type="submit" disabled={!validity.allValid}>
            <span>{validity.allValid ? submitLabel : 'Complete all fields'}</span>
            <i aria-hidden="true">→</i>
          </button>
        )}

        <p className="payment-form__privacy">
          <span aria-hidden="true">◆</span>
          This preview validates locally and never stores or transmits card details.
        </p>
      </form>
    </section>
  );
}
