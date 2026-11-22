import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Palette, Sparkles } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Field, Photo, Pill } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { useToast } from "@/components/ui/use-toast";
import { brandFromImage, fileToDataUrl } from "@/lib/grapion/util";
import { DEFAULT_BRAND } from "@/lib/grapion/store";
import { findGym, updateBranding, updateGym } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/branding")({
  component: BrandingPage,
  head: () => ({ meta: [{ title: "Branding · GRAPION GYM" }] }),
});

const slots = [
  ["primary", "Primary colour"],
  ["secondary", "Secondary colour"],
  ["accent", "Accent colour"],
  ["bg", "Background"],
  ["button", "Button colour"],
  ["text", "Text colour"],
];

function BrandingPage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gym = findGym(db, session?.gymId);
  const [logo, setLogo] = useState(gym?.logo || "");
  const [brand, setBrand] = useState({ ...DEFAULT_BRAND, ...(gym?.brand || {}) });
  const [working, setWorking] = useState(false);

  if (!gym) return null;

  const analyse = async (file) => {
    if (!file) return;
    setWorking(true);
    try {
      const dataUrl = await fileToDataUrl(file, 512);
      setLogo(dataUrl);
      const palette = await brandFromImage(dataUrl);
      if (palette) {
        setBrand((prev) => ({ ...prev, ...palette }));
        toast({ title: "Palette suggested", description: "Colours were read from your logo." });
      }
    } catch (err) {
      toast({ title: "Could not read that image", description: err.message });
    } finally {
      setWorking(false);
    }
  };

  const apply = () => {
    updateGym(gym.id, { logo });
    updateBranding(gym.id, brand);
    toast({ title: "Branding applied", description: "Owner and member areas now use this palette." });
  };

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Branding"
        title="Automatic gym branding"
        description="Upload your logo — colours are read from the image and suggested. Adjust them and apply."
        actions={
          <Button size="sm" onClick={apply}>
            <Palette className="mr-1.5 h-3.5 w-3.5" /> Apply branding
          </Button>
        }
      />

      <div className="grid gap-4 lg:grid-cols-[0.85fr_1.15fr]">
        <Panel title="Logo" subtitle="The original file is never overwritten">
          <div className="flex items-center gap-4">
            <Photo src={logo} name={gym.name} size={72} rounded="rounded-xl" />
            <div className="flex-1">
              <Input
                type="file"
                accept="image/*"
                className="text-[12px]"
                onChange={(e) => analyse(e.target.files?.[0])}
              />
              <p className="mt-1.5 text-[10.5px] text-muted-foreground">
                {working ? "Reading colours…" : "PNG or JPG. Images are downscaled before saving."}
              </p>
            </div>
          </div>

          <div className="mt-5 grid grid-cols-2 gap-3">
            {slots.map(([key, label]) => (
              <Field key={key} label={label}>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    value={brand[key] || "#000000"}
                    onChange={(e) => setBrand({ ...brand, [key]: e.target.value })}
                    className="h-9 w-10 cursor-pointer rounded-md border border-border bg-transparent"
                  />
                  <Input
                    value={brand[key] || ""}
                    onChange={(e) => setBrand({ ...brand, [key]: e.target.value })}
                    className="h-9 text-[11.5px]"
                  />
                </div>
              </Field>
            ))}
          </div>
        </Panel>

        <Panel title="Your brand preview" subtitle="Applied live to both dashboards once saved">
          <div
            className="rounded-2xl border p-5"
            style={{ background: brand.bg, borderColor: `${brand.primary}55` }}
          >
            <div className="flex items-center gap-3">
              {logo ? (
                <img src={logo} alt={gym.name} className="h-10 w-10 rounded-lg object-cover" />
              ) : (
                <div
                  className="grid h-10 w-10 place-items-center rounded-lg text-[12px] font-bold"
                  style={{ background: brand.primary, color: "#111" }}
                >
                  GP
                </div>
              )}
              <div>
                <p className="font-heading text-[13px] font-semibold" style={{ color: brand.text }}>
                  {gym.name}
                </p>
                <p className="text-[10px]" style={{ color: `${brand.text}99` }}>
                  Powered by Grapion Digital
                </p>
              </div>
              <span
                className="ml-auto rounded-full px-2 py-1 text-[9.5px] font-bold uppercase tracking-wider"
                style={{ background: `${brand.accent}22`, color: brand.accent }}
              >
                Active
              </span>
            </div>

            <div className="mt-4 grid grid-cols-3 gap-2">
              {["Members", "Visits today", "Collected"].map((label) => (
                <div
                  key={label}
                  className="rounded-xl border p-2.5"
                  style={{ borderColor: `${brand.text}18`, background: `${brand.text}06` }}
                >
                  <p className="text-[9px]" style={{ color: `${brand.text}80` }}>{label}</p>
                  <p className="mt-1 font-heading text-[15px] font-semibold" style={{ color: brand.text }}>
                    {label === "Collected" ? "₹0" : "0"}
                  </p>
                </div>
              ))}
            </div>

            <div className="mt-4 flex gap-2">
              <button
                className="flex-1 rounded-lg px-3 py-2 text-[11.5px] font-semibold"
                style={{ background: brand.button, color: "#111" }}
              >
                CHECK IN
              </button>
              <button
                className="flex-1 rounded-lg border px-3 py-2 text-[11.5px] font-semibold"
                style={{ borderColor: `${brand.text}33`, color: brand.text }}
              >
                CHECK OUT
              </button>
            </div>
          </div>

          <div className="mt-4 flex items-center gap-2 text-[11px] text-muted-foreground">
            <Sparkles className="h-3.5 w-3.5 text-primary" />
            Suggested colours come from the most vivid part of your logo.
          </div>
          <div className="mt-3 flex flex-wrap gap-2">
            <Pill tone="primary">Owner dashboard</Pill>
            <Pill tone="blue">Member dashboard</Pill>
            <Pill tone="gray">Member sign-in</Pill>
          </div>
        </Panel>
      </div>
    </OwnerShell>
  );
}