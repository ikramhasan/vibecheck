"use client";

import { useState } from "react";
import { Orb, statusLook, type Status } from "./Orb";
import { BuddyOrb, RingOrb } from "./OrbFamilies";

const families = ["Thinking", "Ring", "Buddy"] as const;
type Family = (typeof families)[number];

const statuses: { status: Status; word: string; detail: string }[] = [
  { status: "working", word: "Working", detail: "Running a tool or writing a reply" },
  { status: "asking", word: "Asking", detail: "Waiting on your answer" },
  { status: "blocked", word: "Blocked", detail: "Hit a usage limit" },
  { status: "idle", word: "Your turn", detail: "Done, back to you" },
];

function FamilyOrb({ family, status }: { family: Family; status: Status }) {
  switch (family) {
    case "Thinking":
      return <Orb look={statusLook[status]} size={40} status={status} />;
    case "Ring":
      return <RingOrb status={status} size={34} />;
    case "Buddy":
      return <BuddyOrb status={status} size={40} />;
  }
}

export function StatusShowcase() {
  const [family, setFamily] = useState<Family>("Thinking");

  return (
    <>
      <div className="family-picker" role="radiogroup" aria-label="Orb style">
        {families.map((option) => (
          <button
            key={option}
            type="button"
            role="radio"
            aria-checked={family === option}
            onClick={() => setFamily(option)}
          >
            {option}
          </button>
        ))}
      </div>
      <ul>
        {statuses.map(({ status, word, detail }) => (
          <li key={status}>
            <span className="status-orb" key={family}>
              <FamilyOrb family={family} status={status} />
            </span>
            <strong>{word}</strong>
            <span>{detail}</span>
          </li>
        ))}
      </ul>
    </>
  );
}
