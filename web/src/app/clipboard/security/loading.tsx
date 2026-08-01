import { SkeletonList } from "@/components/ui";

export default function Loading() {
  return (
    <div className="flex flex-col gap-4 py-5">
      <div className="skeleton h-7 w-40 rounded-[--radius-m]" />
      <SkeletonList rows={3} />
    </div>
  );
}
