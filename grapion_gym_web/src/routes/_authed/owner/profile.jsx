import { useState } from "react";
import { createFileRoute } from "@tanstack/react-router";
import { Save } from "lucide-react";
import { OwnerShell } from "@/components/grapion/shells";
import { useRoleSession, useStore } from "@/lib/grapion/useGrapion";
import { PageHead, Panel, Field, Photo } from "@/components/grapion/ui";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useToast } from "@/components/ui/use-toast";
import { fileToDataUrl } from "@/lib/grapion/util";
import { findGym, updateGym } from "@/lib/grapion/repo";

export const Route = createFileRoute("/_authed/owner/profile")({
  component: GymProfilePage,
  head: () => ({ meta: [{ title: "Gym profile · GRAPION GYM" }] }),
});

function GymProfilePage() {
  const session = useRoleSession();
  const db = useStore();
  const { toast } = useToast();
  const gym = findGym(db, session?.gymId);
  const [form, setForm] = useState(() => ({ ...gym }));

  if (!gym) return null;
  const set = (key, value) => setForm((prev) => ({ ...prev, [key]: value }));

  const upload = async (key, file) => {
    if (!file) return;
    try {
      set(key, await fileToDataUrl(file, 512));
    } catch (err) {
      toast({ title: "Upload failed", description: err.message });
    }
  };

  const save = () => {
    updateGym(gym.id, {
      name: form.name,
      phone: form.phone,
      email: form.email,
      address: form.address,
      city: form.city,
      openingHours: form.openingHours,
      description: form.description,
      upiId: form.upiId,
      upiName: form.upiName,
      logo: form.logo,
      upiQr: form.upiQr,
    });
    toast({ title: "Gym profile saved" });
  };

  return (
    <OwnerShell>
      <PageHead
        eyebrow="Profile"
        title="Gym profile"
        description="These details appear on the member dashboard and payment screens."
        actions={
          <Button size="sm" onClick={save}>
            <Save className="mr-1.5 h-3.5 w-3.5" /> Save changes
          </Button>
        }
      />

      <div className="grid gap-4 lg:grid-cols-[1.15fr_0.85fr]">
        <Panel title="Gym details">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Gym name">
              <Input value={form.name || ""} onChange={(e) => set("name", e.target.value)} />
            </Field>
            <Field label="Phone number">
              <Input value={form.phone || ""} onChange={(e) => set("phone", e.target.value)} />
            </Field>
            <Field label="Email">
              <Input value={form.email || ""} onChange={(e) => set("email", e.target.value)} />
            </Field>
            <Field label="City">
              <Input value={form.city || ""} onChange={(e) => set("city", e.target.value)} />
            </Field>
            <Field label="Address" className="sm:col-span-2">
              <Input value={form.address || ""} onChange={(e) => set("address", e.target.value)} />
            </Field>
            <Field label="Opening hours" className="sm:col-span-2">
              <Input
                value={form.openingHours || ""}
                onChange={(e) => set("openingHours", e.target.value)}
                placeholder="Monday – Saturday · 6 AM to 10 PM"
              />
            </Field>
            <Field label="Gym description" className="sm:col-span-2">
              <Textarea
                rows={3}
                value={form.description || ""}
                onChange={(e) => set("description", e.target.value)}
              />
            </Field>
          </div>
        </Panel>

        <div className="space-y-4">
          <Panel title="Gym logo">
            <div className="flex items-center gap-4">
              <Photo src={form.logo} name={form.name} size={64} rounded="rounded-xl" />
              <div className="flex-1">
                <Input
                  type="file"
                  accept="image/*"
                  className="text-[12px]"
                  onChange={(e) => upload("logo", e.target.files?.[0])}
                />
                <p className="mt-1.5 text-[10.5px] text-muted-foreground">
                  Used across owner and member areas. Images are downscaled before saving.
                </p>
              </div>
            </div>
          </Panel>

          <Panel title="UPI payment details" subtitle="Shown to members on renewal screens">
            <div className="space-y-4">
              <Field label="UPI ID">
                <Input
                  value={form.upiId || ""}
                  onChange={(e) => set("upiId", e.target.value)}
                  placeholder="gymname@upi"
                />
              </Field>
              <Field label="Account display name">
                <Input value={form.upiName || ""} onChange={(e) => set("upiName", e.target.value)} />
              </Field>
              <Field label="UPI QR code image">
                <div className="flex items-center gap-3">
                  {form.upiQr ? (
                    <img src={form.upiQr} alt="UPI QR" className="h-16 w-16 rounded-lg border border-border object-cover" />
                  ) : (
                    <div className="grid h-16 w-16 place-items-center rounded-lg border border-dashed border-border text-[9px] text-muted-foreground">
                      No QR
                    </div>
                  )}
                  <Input
                    type="file"
                    accept="image/*"
                    className="text-[12px]"
                    onChange={(e) => upload("upiQr", e.target.files?.[0])}
                  />
                </div>
              </Field>
              <p className="text-[10.5px] leading-relaxed text-muted-foreground">
                Scanning a QR does not confirm payment. Members submit a confirmation that you verify
                manually under Payments.
              </p>
            </div>
          </Panel>
        </div>
      </div>
    </OwnerShell>
  );
}