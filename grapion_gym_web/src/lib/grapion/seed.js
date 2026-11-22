import { addMonths, isoDate, memberCodeFor, uid } from "./util";

const shift = (days) => {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return isoDate(d);
};

const stamp = (date, time) => new Date(`${date}T${time}:00`).toISOString();

export const DEMO_GYM_ID = "gym_demo_nishchay";

/**
 * Demo gym bundle — every record is flagged isDemo so it can be removed
 * cleanly without touching data the user created.
 */
export function buildDemo() {
  const gymId = DEMO_GYM_ID;
  const g = (prefix, n) => `${prefix}_demo_${n}`;

  const services = [
    ["Gym", "Full strength floor access with free weights and machines."],
    ["Cardio", "Treadmills, cross trainers and rowing machines."],
    ["Yoga", "Guided yoga and mobility sessions."],
    ["Zumba", "High energy group dance cardio."],
    ["Steam Bath", "Post-workout recovery steam room."],
  ].map(([name, description], i) => ({
    id: g("svc", i + 1),
    gymId,
    name,
    description,
    status: "active",
    isDemo: true,
  }));

  const plans = [
    ["Monthly Gym Package", 1, 999, "1 month full gym access", ["Gym"]],
    ["Quarterly Gym Package", 3, 2499, "3 months with all core services", ["Gym", "Cardio"]],
    ["Half-Yearly Package", 6, 4499, "6 months with recovery access", ["Gym", "Cardio", "Steam Bath"]],
    ["Yearly Package", 12, 7999, "Best value annual membership", ["Gym", "Cardio", "Yoga", "Steam Bath"]],
  ].map(([name, months, price, description, svc], i) => ({
    id: g("plan", i + 1),
    gymId,
    name,
    durationMonths: months,
    price,
    description,
    services: services.filter((s) => svc.includes(s.name)).map((s) => s.id),
    status: "active",
    isDemo: true,
  }));

  const trainers = [
    ["Rohit Verma", "Strength & Conditioning", "9822011456"],
    ["Ananya Rao", "Yoga & Mobility", "9822017788"],
  ].map(([name, specialization, phone], i) => ({
    id: g("trn", i + 1),
    gymId,
    name,
    photo: "",
    phone,
    email: `${name.split(" ")[0].toLowerCase()}@nishchayfitness.in`,
    specialization,
    joiningDate: shift(-240 + i * 40),
    status: "active",
    isDemo: true,
  }));

  const batches = [
    ["Morning 6–7 AM", "06:00", "07:00", trainers[0].id, services[0].id, 30],
    ["Morning 7–8 AM", "07:00", "08:00", trainers[1].id, services[2].id, 25],
    ["Evening 6–7 PM", "18:00", "19:00", trainers[0].id, services[1].id, 30],
    ["Evening 7–8 PM", "19:00", "20:00", trainers[0].id, services[0].id, 30],
  ].map(([name, startTime, endTime, trainerId, serviceId, capacity], i) => ({
    id: g("batch", i + 1),
    gymId,
    name,
    startTime,
    endTime,
    days: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    trainerId,
    serviceId,
    capacity,
    status: "active",
    isDemo: true,
  }));

  const people = [
    ["Rahul Mehta", "Male", "9822012345", 5, 3, 0],
    ["Priya Sharma", "Female", "9822013456", 2, 1, 300],
    ["Arjun Nair", "Male", "9822014567", 120, 4, 0],
    ["Sneha Kulkarni", "Female", "9822015678", -4, 1, 0],
    ["Vikram Singh", "Male", "9822016789", 21, 3, 0],
    ["Aisha Khan", "Female", "9822017890", 1, 1, 0],
  ];

  const members = people.map(([name, gender, phone, expiryOffset, planIdx, pending], i) => ({
    id: g("mem", i + 1),
    code: memberCodeFor("Nishchay Fitness", i + 1),
    gymId,
    name,
    photo: "",
    phone,
    email: `${name.split(" ")[0].toLowerCase()}@member.nishchay.in`,
    password: "member1234",
    gender,
    dob: "",
    occupation: i % 2 === 0 ? "Software Engineer" : "Student",
    address: "Vijay Nagar, Indore",
    emergencyContact: "9822000000",
    notes: "",
    status: "active",
    joinedAt: shift(-expiryOffset - 60),
    batchId: batches[i % batches.length].id,
    isDemo: true,
    pendingHint: pending,
  }));

  const memberships = members.map((m, i) => {
    const plan = plans[people[i][4] - 1];
    const expiry = shift(people[i][3]);
    return {
      id: g("mship", i + 1),
      gymId,
      memberId: m.id,
      planId: plan.id,
      batchId: m.batchId,
      joiningDate: shift(-expiry * 0 - 90),
      startDate: addMonths(expiry, -plan.durationMonths),
      expiryDate: expiry,
      totalAmount: plan.price,
      paidAmount: plan.price - people[i][5],
      status: "active",
      createdAt: new Date().toISOString(),
      isDemo: true,
    };
  });

  const payments = memberships.map((ms, i) => ({
    id: g("pay", i + 1),
    gymId,
    memberId: ms.memberId,
    membershipId: ms.id,
    planId: ms.planId,
    amount: ms.paidAmount,
    date: ms.startDate,
    method: i % 3 === 0 ? "upi" : "cash",
    status: "verified",
    type: "membership",
    notes: "Membership purchase",
    verifiedAt: stamp(ms.startDate, "11:20"),
    verifiedBy: "Nishchay Sharma",
    createdAt: stamp(ms.startDate, "11:10"),
    isDemo: true,
  }));

  const pending = [
    {
      id: g("pay", 20),
      gymId,
      memberId: members[5].id,
      membershipId: "",
      planId: plans[0].id,
      amount: 999,
      date: shift(0),
      method: "upi",
      status: "pending",
      type: "renewal",
      notes: "UPI ref 421398220145",
      createdAt: stamp(shift(0), "08:12"),
      isDemo: true,
    },
    {
      id: g("pay", 21),
      gymId,
      memberId: members[1].id,
      membershipId: memberships[1].id,
      planId: plans[0].id,
      amount: 300,
      date: shift(-1),
      method: "cash",
      status: "pending",
      type: "membership",
      notes: "Balance payment promised",
      createdAt: stamp(shift(-1), "18:40"),
      isDemo: true,
    },
  ];

  const attendance = [
    { memberIdx: 0, day: 0, in: "06:42", out: null },
    { memberIdx: 1, day: 0, in: "07:05", out: "08:12" },
    { memberIdx: 2, day: 0, in: "18:22", out: null },
    { memberIdx: 3, day: 0, in: "19:03", out: "20:10" },
    { memberIdx: 0, day: -1, in: "06:38", out: "08:02" },
    { memberIdx: 2, day: -1, in: "18:30", out: "19:45" },
    { memberIdx: 4, day: -1, in: "07:12", out: "08:20" },
    { memberIdx: 1, day: -2, in: "06:55", out: "08:05" },
    { memberIdx: 5, day: -2, in: "19:10", out: "20:15" },
    { memberIdx: 0, day: -3, in: "06:40", out: "08:00" },
    { memberIdx: 4, day: -4, in: "07:00", out: "08:12" },
    { memberIdx: 2, day: -5, in: "18:35", out: "19:50" },
  ].map((a, i) => {
    const date = shift(a.day);
    return {
      id: g("att", i + 1),
      gymId,
      memberId: members[a.memberIdx].id,
      date,
      checkIn: stamp(date, a.in),
      checkOut: a.out ? stamp(date, a.out) : null,
      isDemo: true,
    };
  });

  return {
    gym: {
      id: gymId,
      name: "Nishchay Fitness",
      phone: "9822011223",
      email: "hello@nishchayfitness.in",
      address: "2nd Floor, Apollo Trade Centre, Vijay Nagar",
      city: "Indore",
      description: "Premium strength and conditioning studio in the heart of Indore.",
      openingHours: "Monday – Saturday · 5:30 AM to 10:30 PM",
      logo: "",
      upiId: "nishchayfitness@upi",
      upiName: "Nishchay Fitness",
      upiQr: "",
      status: "active",
      brand: null,
      createdAt: shift(-210),
      isDemo: true,
    },
    owner: {
      id: g("owner", 1),
      gymId,
      name: "Nishchay Sharma",
      email: "owner@nishchayfitness.in",
      phone: "9822011223",
      password: "demo1234",
      status: "active",
      createdAt: shift(-210),
      isDemo: true,
    },
    services,
    plans,
    trainers,
    batches,
    members: members.map(({ pendingHint, ...m }) => m),
    memberships,
    payments: [...payments, ...pending],
    attendance,
    subscription: {
      id: g("sub", 1),
      gymId,
      planName: "Yearly Subscription",
      cycle: "yearly",
      price: 12999,
      startDate: shift(-330),
      expiryDate: shift(35),
      history: [{ startDate: shift(-330), expiryDate: shift(35), cycle: "yearly", amount: 12999, at: shift(-330) }],
      isDemo: true,
    },
  };
}

export { uid };