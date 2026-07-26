"""
Port of server/src/escalation.js -- the "ask user" box in the flow.

The JS original held escalations in an in-process `Map` of unresolved
promises, which is why a server restart silently dropped every outstanding
question and why "show me what this developer is waiting on" meant scanning
that Map by hand. Here an escalation is a node on the graph, owned by the
developer it belongs to, so it survives a restart and "what is dev_x waiting
on" is a one-hop traversal that cannot see anyone else's conflicts.
"""

import from datetime { datetime, timezone, timedelta }
import secrets;
import from identity { Developer, find_developer, now_iso }


glob DEFAULT_TIMEOUT_SECONDS: int = 300;


node Escalation {
    has conflict_id: str;
    has dev_id: str;
    has title: str;
    has reason: str;
    has created_at: str;
    has expires_at: str;
    has path: str = "";
    has status: str = "open";        # open | resolved | expired | withdrawn
    has choice: str = "";
    has custom_text: str = "";
    has resolved_at: str = "";
}

edge AskedOf {}


obj EscalationOption {
    has id: str;
    has label: str;
    has detail: str = "";
    has input: bool = False;
}


"""Used when the agent asks a question but proposes no choices of its own.
The ids matter: "green" keeps the pusher's intent, "red" defers to what is
already on main, and those ids drive the button colours the notch renders."""
glob DEFAULT_OPTIONS: list[EscalationOption] = [
    EscalationOption(
        id="green",
        label="Keep mine",
        detail="Apply my change as intended and adapt the current code around it."
    ),
    EscalationOption(
        id="red",
        label="Keep theirs",
        detail="Leave the current code as it is and drop the conflicting part of my change."
    ),
    EscalationOption(id="other", label="Instruct", input=True),
];


def _expiry(seconds: int) -> str {
    return (datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat();
}


def is_expired(escalation: Escalation) -> bool {
    if not escalation.expires_at {
        return False;
    }
    return datetime.fromisoformat(escalation.expires_at) <= datetime.now(timezone.utc);
}


def find_escalation(wanted: str) -> Escalation | None {
    found = [root -->[?:Escalation, conflict_id == wanted]];
    return found[0] if found else None;
}


"""Every open question for one developer. The traversal starts from the
developer node, so a caller structurally cannot reach anyone else's -- the JS
version had to filter a shared Map and remember to check dev ownership on
every path."""
def pending_for(dev_id: str) -> list[Escalation] {
    dev = find_developer(dev_id);
    if dev is None {
        return [];
    }
    open_ones: list[Escalation] = [];
    for esc in [dev <-:AskedOf:<-[?:Escalation]] {
        if esc.status == "open" {
            if is_expired(esc) {
                esc.status = "expired";
            } else {
                open_ones.append(esc);
            }
        }
    }
    return open_ones;
}


"""Raise the question and hand it to the developer's surface. Returns the
Escalation node; the caller waits for it to leave `open`."""
walker Ask {
    has dev_id: str;
    has title: str;
    has reason: str;
    has path: str = "";
    has timeout_seconds: int = 0;

    can ask with Root entry {
        dev = find_developer(self.dev_id);
        if dev is None {
            report {"error": "no_notch", "message": f"No developer registered as {self.dev_id}."};
            disengage;
        }
        seconds = self.timeout_seconds if self.timeout_seconds > 0 else DEFAULT_TIMEOUT_SECONDS;
        escalation = Escalation(
            conflict_id=f"c_{secrets.token_hex(4)}",
            dev_id=self.dev_id,
            title=self.title,
            reason=self.reason,
            created_at=now_iso(),
            expires_at=_expiry(seconds),
            path=self.path
        );
        root ++> escalation;
        escalation +>:AskedOf:+> dev;
        report {
            "conflict_id": escalation.conflict_id,
            "dev_id": escalation.dev_id,
            "title": escalation.title,
            "reason": escalation.reason,
            "path": escalation.path,
            "expires_at": escalation.expires_at,
            "options": [
                {"id": o.id, "label": o.label, "detail": o.detail, "input": o.input}
                for o in DEFAULT_OPTIONS
            ],
        };
    }
}


"""The developer's answer. A client may only ever resolve its own conflicts:
the walker carries the dev_id its bearer token proved, and refuses anything
that is not reachable from that developer."""
walker Resolve {
    has conflict_id: str;
    has dev_id: str;
    has choice: str;
    has custom_text: str = "";

    can resolve with Root entry {
        escalation = find_escalation(self.conflict_id);
        if escalation is None or escalation.dev_id != self.dev_id {
            report {"status": "error", "message": "That decision is no longer open."};
            disengage;
        }
        if escalation.status != "open" {
            report {"status": "error", "message": f"Already {escalation.status}."};
            disengage;
        }
        if is_expired(escalation) {
            escalation.status = "expired";
            report {"status": "error", "message": "The question timed out before you answered it."};
            disengage;
        }
        escalation.status = "resolved";
        escalation.choice = self.choice;
        escalation.custom_text = self.custom_text;
        escalation.resolved_at = now_iso();
        report {
            "status": "applied",
            "conflict_id": escalation.conflict_id,
            "choice": escalation.choice,
            "custom_text": escalation.custom_text,
        };
    }
}


"""What this developer is waiting on -- the reconnect catch-up the notch runs
on every socket open."""
walker Pending {
    has dev_id: str;

    can list with Root entry {
        report [
            {
                "conflict_id": e.conflict_id,
                "title": e.title,
                "reason": e.reason,
                "path": e.path,
                "expires_at": e.expires_at,
            }
            for e in pending_for(self.dev_id)
        ];
    }
}


"""Cancel an outstanding escalation -- the push was abandoned, or the server
is shutting down."""
walker Withdraw {
    has conflict_id: str;
    has reason: str = "superseded";

    can withdraw with Root entry {
        escalation = find_escalation(self.conflict_id);
        if escalation is None or escalation.status != "open" {
            report {"withdrawn": False};
            disengage;
        }
        escalation.status = "withdrawn";
        report {"withdrawn": True, "conflict_id": escalation.conflict_id, "reason": self.reason};
    }
}
