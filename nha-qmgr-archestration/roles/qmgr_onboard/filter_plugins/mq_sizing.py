from ansible.errors import AnsibleFilterError
import re

def parse_storage_bytes(storage_str):
    """
    Parses a storage string like '5Gi' or '5G' or '500Mi' into bytes.
    Matches the playbook's regex substitution behavior and human_to_bytes.
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

    for tier_name in tier_order:
        if tier_name not in sizing_dict:
            continue
            
        tier_specs = sizing_dict[tier_name]
        qmgr_storage_str = tier_specs.get('qmgr_storage', '0G')
        
        try:
            tier_bytes = parse_storage_bytes(qmgr_storage_str)
        except AnsibleFilterError as e:
            continue
            
        if tier_bytes >= computed_bytes:
            # We found a match
            return {
                "name": tier_name,
                "specs": tier_specs
            }
            
    # If no tier matches, format the error exactly like the playbook did
    last_tier = tier_order[-1] if tier_order else 'unknown'
    last_tier_str = sizing_dict.get(last_tier, {}).get('qmgr_storage', '0G')
    last_tier_bytes = parse_storage_bytes(last_tier_str)
    
    req_gb = bytes_to_gb(computed_bytes)
    max_gb = bytes_to_gb(last_tier_bytes)
    
    raise AnsibleFilterError(
        f"No sizing tier in {env_name} can satisfy computed storage of {req_gb}. "
        f"Maximum available: {max_gb} (tier '{last_tier}'). "
        f"Consider adding a larger tier or reducing total_volume_24h / avg_msg_size."
    )

class FilterModule(object):
    """
    Ansible filter mapping
    """
    def filters(self):
        return {
            'get_best_mq_tier': get_best_mq_tier
        }
