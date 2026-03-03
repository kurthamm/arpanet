"""Configuration parser for ARPANET script.

Parses the IMPS and NCPS bash arrays from the arpanet shell script.
"""

import re
from dataclasses import dataclass
from typing import List, Tuple
from pathlib import Path


@dataclass
class IMPConfig:
    """Configuration for a single IMP."""
    number: int          # IMP number (01-99)
    name: str            # Human-readable name (e.g., "UCLA")

    @property
    def num_str(self) -> str:
        """Return zero-padded IMP number string."""
        return f"{self.number:02d}"


@dataclass
class NCPConfig:
    """Configuration for a single NCP daemon."""
    imp: int             # IMP number this NCP connects to
    host_idx: int        # Host index within IMP (0, 1, 2, ...)
    full_host: int       # Full ARPANET host number
    tx_port: int         # Transmit port
    rx_port: int         # Receive port
    hostname: str        # Human-readable hostname

    @property
    def host_str(self) -> str:
        """Return zero-padded host number string."""
        return f"{self.full_host:02d}"


def parse_arpanet_script(path: str) -> Tuple[List[IMPConfig], List[NCPConfig]]:
    """Parse IMPS and NCPS arrays from the arpanet bash script.

    Args:
        path: Path to the arpanet script

    Returns:
        Tuple of (IMP configs, NCP configs)
    """
    content = Path(path).read_text()

    imps = _parse_imps(content)
    ncps = _parse_ncps(content)

    return imps, ncps


def _parse_imps(content: str) -> List[IMPConfig]:
    """Parse the IMPS array from script content."""
    imps = []

    # Find the IMPS array block
    imps_match = re.search(
        r'declare\s+-a\s+IMPS=\(\s*(.*?)\s*\)',
        content,
        re.DOTALL
    )

    if not imps_match:
        raise ValueError("Could not find IMPS array in script")

    array_content = imps_match.group(1)

    # Extract each entry, skipping comments
    for line in array_content.split('\n'):
        line = line.strip()

        # Skip empty lines and comments
        if not line or line.startswith('#'):
            continue

        # Match quoted entry: "NN:NAME"
        entry_match = re.match(r'"(\d+):([^"]+)"', line)
        if entry_match:
            num = int(entry_match.group(1))
            name = entry_match.group(2)
            imps.append(IMPConfig(number=num, name=name))

    return sorted(imps, key=lambda x: x.number)


def _parse_ncps(content: str) -> List[NCPConfig]:
    """Parse the NCPS array from script content."""
    ncps = []

    # Find the NCPS array block
    ncps_match = re.search(
        r'declare\s+-a\s+NCPS=\(\s*(.*?)\s*\)',
        content,
        re.DOTALL
    )

    if not ncps_match:
        raise ValueError("Could not find NCPS array in script")

    array_content = ncps_match.group(1)

    # Extract each entry, skipping comments
    for line in array_content.split('\n'):
        line = line.strip()

        # Skip empty lines and comments (lines starting with # or #")
        if not line or line.startswith('#'):
            continue

        # Match quoted entry: "imp:host_idx:full_host:tx_port:rx_port:hostname"
        entry_match = re.match(
            r'"(\d+):(\d+):(\d+):(\d+):(\d+):([^"]+)"',
            line
        )
        if entry_match:
            ncps.append(NCPConfig(
                imp=int(entry_match.group(1)),
                host_idx=int(entry_match.group(2)),
                full_host=int(entry_match.group(3)),
                tx_port=int(entry_match.group(4)),
                rx_port=int(entry_match.group(5)),
                hostname=entry_match.group(6)
            ))

    return sorted(ncps, key=lambda x: x.full_host)


def get_imp_by_number(imps: List[IMPConfig], number: int) -> IMPConfig:
    """Find IMP config by number."""
    for imp in imps:
        if imp.number == number:
            return imp
    raise KeyError(f"IMP {number} not found")


def get_imp_by_name(imps: List[IMPConfig], name: str) -> IMPConfig:
    """Find IMP config by name (case-insensitive)."""
    name_lower = name.lower()
    for imp in imps:
        if imp.name.lower() == name_lower:
            return imp
    raise KeyError(f"IMP '{name}' not found")


def resolve_imp_target(imps: List[IMPConfig], target: str) -> IMPConfig:
    """Resolve a target string to an IMP config.

    Target can be:
    - A number: "5", "05"
    - A name: "UCLA", "BBN"
    """
    # Try as number first
    try:
        num = int(target)
        return get_imp_by_number(imps, num)
    except ValueError:
        pass

    # Try as name
    return get_imp_by_name(imps, target)
