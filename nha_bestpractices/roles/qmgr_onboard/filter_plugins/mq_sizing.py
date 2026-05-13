from ansible.errors import AnsibleFilterError
import re


def parse_volume_count(value_str):
    """
    Parses a human-friendly volume COUNT string using SI decimal multipliers.

    This is for message counts (total_volume_24h), NOT storage sizes.
    Examples:
        '1k'   -> 1,000
        '500k' -> 500,000
        '1m'   -> 1,000,000
        '10m'  -> 10,000,000
        '1g'   -> 1,000,000,000
        '5000' -> 5,000

    IMPORTANT: This uses base-10 (SI) multipliers, not base-2 (IEC).
    For storage sizes (e.g., '5Gi'), use parse_storage_bytes instead.
    """
    if not value_str:
        return 0

    value_str = str(value_str).strip().lower()

    si_suffixes = {
        'k': 1_000,
        'm': 1_000_000,
        'g': 1_000_000_000,
        't': 1_000_000_000_000,
    }

    match = re.match(r'^(\d+(?:\.\d+)?)\s*([kmgt])?$', value_str)
    if match:
        val = float(match.group(1))
        suffix = match.group(2)
        if suffix:
            val *= si_suffixes[suffix]
        return int(val)

    try:
        return int(value_str)
    except ValueError:
        raise AnsibleFilterError(
            f"Cannot parse volume count '{value_str}'. "
            f"Use a plain number or SI suffix: 1k, 500k, 1m, 10m, 1g."
        )


def parse_storage_bytes(storage_str):
    """
    Parses a storage string like '5Gi' or '5G' or '500Mi' into bytes.
    Uses base-2 (IEC) multipliers: 1K=1024, 1M=1048576, etc.
    """
    if not storage_str:
        return 0

    # Strip optional 'i' and 'B' at the end (e.g., '5Gi' -> '5G')
    storage_str = re.sub(r'([KMGTPE])i?B?$', r'\1', str(storage_str).strip(), flags=re.IGNORECASE)

    suffixes = {
        'K': 1024,
        'M': 1024**2,
        'G': 1024**3,
        'T': 1024**4,
        'P': 1024**5,
        'E': 1024**6,
    }

    match = re.match(r'^(\d+(?:\.\d+)?)\s*([KMGTPE])?$', storage_str, re.IGNORECASE)
    if match:
        val = float(match.group(1))
        suffix = match.group(2)
        if suffix:
            val *= suffixes[suffix.upper()]
        return int(val)

    try:
        return int(storage_str)
    except ValueError:
        raise AnsibleFilterError(f"Cannot parse storage string: {storage_str}")


def bytes_to_gb(byte_val):
    """
    Converts bytes to gigabytes formatting (base 2 - GiB) formatted as GB
    to match the previous ansible human_readable output.
    """
    gb = float(byte_val) / (1024**3)
    return f"{gb:.2f} GB"


def get_best_mq_tier(sizing_dict, computed_bytes, tier_order, env_name):
    """
    Ansible filter to compute the best matching MQ size tier.

    Usage:
    {{ sizing['DEV'] | get_best_mq_tier(computed_storage_bytes, _tier_order, 'DEV') }}

    Returns a dict with 'name' and 'specs', or raises an error.
    """
    try:
        computed_bytes = int(computed_bytes)
    except (ValueError, TypeError):
        raise AnsibleFilterError(f"Invalid computed_bytes provided: {computed_bytes}")

    available_tiers = [tier_name for tier_name in tier_order if tier_name in sizing_dict]
    if not available_tiers:
        raise AnsibleFilterError(
            f"No sizing tiers are configured for environment {env_name}."
        )

    for tier_name in available_tiers:
        tier_specs = sizing_dict[tier_name]
        qmgr_storage_str = tier_specs.get('qmgr_storage', '0G')
        log_storage_str = tier_specs.get('log_storage', '0G')

        try:
            qmgr_bytes = parse_storage_bytes(qmgr_storage_str)
            log_bytes = parse_storage_bytes(log_storage_str)
        except AnsibleFilterError:
            continue

        if qmgr_bytes >= computed_bytes and log_bytes >= computed_bytes:
            return {
                "name": tier_name,
                "specs": tier_specs
            }

    # If no tier matches, report the actual largest configured tier for the environment.
    last_tier = available_tiers[-1]
    last_tier_str = sizing_dict.get(last_tier, {}).get('qmgr_storage', '0G')
    last_tier_bytes = parse_storage_bytes(last_tier_str)

    req_gb = bytes_to_gb(computed_bytes)
    max_gb = bytes_to_gb(last_tier_bytes)

    raise AnsibleFilterError(
        f"No sizing tier in {env_name} can satisfy computed storage of {req_gb}. "
        f"Maximum allowed capacity in {env_name} is {max_gb} (tier '{last_tier}'). "
        f"Consider adding a larger tier or reducing total_volume_24h / avg_msg_size."
    )


class FilterModule(object):
    """
    Ansible filter mapping
    """
    def filters(self):
        return {
            'get_best_mq_tier': get_best_mq_tier,
            'parse_storage_bytes': parse_storage_bytes,
            'parse_volume_count': parse_volume_count,
        }
