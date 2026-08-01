import { SkeletonList } from "@/components/ui";

/**
 * Shown the instant a navigation starts, so a page change registers before the
 * data arrives. Without this the app appears to hang while the server renders.
 */
export default function Loading() {
  return (
    <div className="flex flex-col gap-4 py-5">
      <div className="skeleton h-10 rounded-[--radius-m]" />
      <div className="flex gap-2">
        {[64, 56, 60, 72].map((w, i) => (
          <div key={i} className="skeleton h-8 rounded-full" style={{ width: w }} />
        ))}
      </div>
      <SkeletonList rows={4} />
    </div>
  );
}
