"""Status display formatting for CLI output."""

import time
from typing import Dict, List, Any, Optional


class StatusDisplay:
    """Formats NOC status for terminal display."""

    # ANSI color codes
    RESET = "\033[0m"
    BOLD = "\033[1m"
    RED = "\033[31m"
    GREEN = "\033[32m"
    YELLOW = "\033[33m"
    BLUE = "\033[34m"
    CYAN = "\033[36m"
    DIM = "\033[2m"

    STATE_COLORS = {
        "RUNNING": GREEN,
        "HALTED": YELLOW,
        "STARTING": BLUE,
        "CRASHED": RED,
        "STOPPED": DIM,
    }

    def __init__(self, use_color: bool = True):
        self.use_color = use_color

    def _color(self, text: str, color: str) -> str:
        """Apply color to text if colors are enabled."""
        if self.use_color:
            return f"{color}{text}{self.RESET}"
        return text

    def _state_color(self, state: str) -> str:
        """Get colored state string."""
        color = self.STATE_COLORS.get(state, "")
        return self._color(state, color)

    def format_status_table(self, data: Dict[str, Any]) -> str:
        """Format full status as a table."""
        lines = []

        # IMPs
        imps = data.get("imps", [])
        if imps:
            lines.append(self._color("IMPs:", self.BOLD))
            lines.append(self._format_imp_header())
            lines.append("-" * 70)

            for imp in imps:
                lines.append(self._format_imp_row(imp))

            # Summary
            running = sum(1 for i in imps if i["state"] == "RUNNING")
            halted = sum(1 for i in imps if i["state"] == "HALTED")
            crashed = sum(1 for i in imps if i["state"] == "CRASHED")
            lines.append("-" * 70)
            lines.append(f"Total: {len(imps)}  "
                        f"{self._color(f'Running: {running}', self.GREEN)}  "
                        f"{self._color(f'Halted: {halted}', self.YELLOW)}  "
                        f"{self._color(f'Crashed: {crashed}', self.RED)}")
            lines.append("")

        # NCPs
        ncps = data.get("ncps", [])
        if ncps:
            lines.append(self._color("NCPs:", self.BOLD))
            lines.append(self._format_ncp_header())
            lines.append("-" * 60)

            for ncp in ncps:
                lines.append(self._format_ncp_row(ncp))

            # Summary
            running = sum(1 for n in ncps if n["state"] == "RUNNING")
            lines.append("-" * 60)
            lines.append(f"Total: {len(ncps)}  "
                        f"{self._color(f'Running: {running}', self.GREEN)}")

        return "\n".join(lines)

    def _format_imp_header(self) -> str:
        """Format IMP table header."""
        return f"{'IMP':>4}  {'Name':<12}  {'State':<10}  {'PID':>7}  {'Lights':<8}  {'Restarts':>8}"

    def _format_imp_row(self, imp: Dict) -> str:
        """Format a single IMP row."""
        num = f"{imp['number']:02d}"
        name = imp['name'][:12]
        state = self._state_color(f"{imp['state']:<10}")
        pid = str(imp['pid'] or "-")
        lights = imp['lights'] or "-"
        restarts = str(imp['restarts'])
        attached = " *" if imp.get('attached_client') else ""

        return f"{num:>4}  {name:<12}  {state}  {pid:>7}  {lights:<8}  {restarts:>8}{attached}"

    def _format_ncp_header(self) -> str:
        """Format NCP table header."""
        return f"{'Host':>4}  {'Name':<16}  {'IMP':>4}  {'State':<10}  {'PID':>7}"

    def _format_ncp_row(self, ncp: Dict) -> str:
        """Format a single NCP row."""
        host = f"{ncp['host']:02d}"
        name = ncp['name'][:16]
        imp = f"{ncp['imp']:02d}"
        state = self._state_color(f"{ncp['state']:<10}")
        pid = str(ncp['pid'] or "-")

        return f"{host:>4}  {name:<16}  {imp:>4}  {state}  {pid:>7}"

    def format_imp_detail(self, data: Dict[str, Any]) -> str:
        """Format detailed single IMP status."""
        imp = data.get("imp", data)
        lines = []

        lines.append(self._color(f"IMP {imp['number']:02d}: {imp['name']}", self.BOLD))
        lines.append(f"  State:    {self._state_color(imp['state'])}")
        lines.append(f"  PID:      {imp.get('pid') or 'N/A'}")
        lines.append(f"  Lights:   {imp.get('lights') or 'N/A'}")
        lines.append(f"  Restarts: {imp.get('restarts', 0)}")

        if imp.get('lights_timestamp'):
            ts = time.strftime("%H:%M:%S", time.localtime(imp['lights_timestamp']))
            lines.append(f"  Last update: {ts}")

        if imp.get('attached_client'):
            lines.append(f"  {self._color('Attached:', self.YELLOW)} {imp['attached_client']}")

        return "\n".join(lines)

    def format_lights_table(self, data: Dict[str, Any]) -> str:
        """Format lights for all IMPs."""
        lights = data.get("lights", {})
        lines = []

        lines.append(self._color("IMP Lights:", self.BOLD))
        lines.append(f"{'IMP':>4}  {'Name':<12}  {'Lights':<10}  {'Time':<10}")
        lines.append("-" * 45)

        for imp_num in sorted(lights.keys(), key=int):
            info = lights[imp_num]
            name = info['name'][:12]
            value = info['lights'] or "-"
            ts = ""
            if info.get('timestamp'):
                ts = time.strftime("%H:%M:%S", time.localtime(info['timestamp']))

            lines.append(f"{int(imp_num):4d}  {name:<12}  {value:<10}  {ts:<10}")

        return "\n".join(lines)

    def format_history(self, data: Dict[str, Any]) -> str:
        """Format lights history for an IMP."""
        lines = []

        lines.append(self._color(f"Lights History: IMP {data['imp']:02d} ({data['name']})", self.BOLD))
        lines.append(f"{'Time':<12}  {'Lights':<10}")
        lines.append("-" * 25)

        for entry in data.get('history', []):
            ts = time.strftime("%H:%M:%S", time.localtime(entry['timestamp']))
            lines.append(f"{ts:<12}  {entry['value']:<10}")

        if not data.get('history'):
            lines.append("  (no history)")

        return "\n".join(lines)

    def format_event(self, event: Dict[str, Any]) -> str:
        """Format a single event for streaming display."""
        event_type = event.get("event", "unknown")

        if event_type == "lights":
            ts = time.strftime("%H:%M:%S", time.localtime(event.get('timestamp', time.time())))
            return f"[{ts}] IMP {event['imp']:02d} lights: {event['value']}"

        elif event_type == "state":
            ts = time.strftime("%H:%M:%S")
            old = event.get('old', '?')
            new = event.get('new', '?')
            return f"[{ts}] IMP {event['imp']:02d}: {old} -> {self._state_color(new)}"

        elif event_type == "output":
            return event.get('data', '')

        elif event_type == "restart":
            ts = time.strftime("%H:%M:%S")
            return f"[{ts}] IMP {event['imp']:02d}: RESTART"

        else:
            return f"[event] {event}"

    def format_error(self, error: str) -> str:
        """Format an error message."""
        return self._color(f"Error: {error}", self.RED)

    def format_success(self, message: str) -> str:
        """Format a success message."""
        return self._color(message, self.GREEN)
