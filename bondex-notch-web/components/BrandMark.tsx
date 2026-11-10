import Image from 'next/image';

type BrandMarkProps = {
  className?: string;
};

export default function BrandMark({ className = 'brand__mark' }: BrandMarkProps) {
  return (
    <Image
      src="/brand/bondex-notch-symbol.svg"
      alt=""
      width={100}
      height={100}
      className={className}
      aria-hidden="true"
      unoptimized
    />
  );
}
