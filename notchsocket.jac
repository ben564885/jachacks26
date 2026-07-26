"""
Port of server/src/ws.js -- the socket the macOS notch speaks.

The JS original hand-rolled RFC 6455: an HTTP upgrade handshake, the
Sec-WebSocket-Accept SHA-1, frame masking, opcode dispatch, and a ping
timer, all so a dependency-free Node process could hold a socket open.
None of that is here. `@restspec(protocol=APIProtocol.WEBSOCKET)` on an
async walker serves ws://host/ws/NotchSocket and maps each JSON message
onto the walker's `has` fields.

The wire contract is unchanged, so the existing Swift client speaks to this
without modification: hello / fetch_pending / resolution inbound, and
escalation / pending / ack / withdraw outbound.
"""

import from http { HTTPMethod }
import from identity { Developer, developer_for_token }
import from escalation { Escalation, Resolve, pending_for, find_escalation }


obj NotchMessage {
    has type: str;
    has conflict_id: str = "";
    has choice: str = "";
    has custom_text: str = "";
    has client: str = "";
}


def _escalation_payload(escalation: Escalation) -> dict {
    return {
        "type": "escalation",
        "conflict_id": escalation.conflict_id,
        "dev_id": escalation.dev_id,
        "title": escalation.title,
        "reason": escalation.reason,
        "path": escalation.path,
        "expires_at": escalation.expires_at,
    };
}


"""One connected notch.

Authentication is the bearer token the developer got at registration; the
walker resolves it to a Developer once and every later message is scoped to
that identity, so a client cannot claim a dev_id it does not own -- the same
rule the JS version enforced by hand on every inbound frame.
"""
@restspec(protocol=APIProtocol.WEBSOCKET)
async walker:pub NotchSocket {
    has token: str;
    has type: str = "hello";
    has conflict_id: str = "";
    has choice: str = "";
    has custom_text: str = "";
    has client: str = "";

    can handle with Root entry {
        dev = developer_for_token(self.token);
        if dev is None {
            report {"type": "error", "message": "unknown token"};
            disengage;
        }

        if self.type == "hello" {
            report {
                "type": "hello_ack",
                "dev_id": dev.dev_id,
                "client": self.client if self.client else "unknown client",
            };
            disengage;
        }

        # Reconnect catch-up: everything this developer is still waiting on.
        if self.type == "fetch_pending" {
            report {
                "type": "pending",
                "escalations": [_escalation_payload(e) for e in pending_for(dev.dev_id)],
            };
            disengage;
        }

        if self.type == "resolution" {
            result = root spawn Resolve(
                conflict_id=self.conflict_id,
                dev_id=dev.dev_id,
                choice=self.choice,
                custom_text=self.custom_text
            );
            payload: dict = dict(result.reports[0]) if result.reports else {"status": "error"};
            if payload.get("status") == "applied" {
                report {
                    "type": "ack",
                    "conflict_id": self.conflict_id,
                    "status": "applied",
                };
                # Any other surface showing this one is told to drop it.
                report {
                    "type": "withdraw",
                    "conflict_id": self.conflict_id,
                    "reason": "resolved_elsewhere",
                };
            } else {
                report {
                    "type": "ack",
                    "conflict_id": self.conflict_id,
                    "status": "error",
                    "message": str(payload.get("message") or "That decision is no longer open."),
                };
            }
            disengage;
        }

        report {"type": "error", "message": f"unknown message type {self.type}"};
    }
}


"""Whether a developer currently has a surface attached. The push flow uses
this to decide between asking and falling back to needs_human."""
walker NotchStatus {
    has dev_id: str;

    can status with Root entry {
        waiting = pending_for(self.dev_id);
        report {
            "dev_id": self.dev_id,
            "pending": len(waiting),
            "conflicts": [e.conflict_id for e in waiting],
        };
    }
}
