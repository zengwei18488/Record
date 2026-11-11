import json
import sqlite3
import sys

def clean_version(version):
    """
    Strips non-standard version prefixes commonly rejected by NVD dictionary standards
    e.g., 'v5.8.7' -> '5.8.7'
    """
    if version.startswith('v') and len(version) > 1:
        return version[1:]
    return version

def parse_purl_base(purl_string):
    """
    Extracts the normalized base PURL without version suffix and qualifiers
    e.g., 'pkg:generic/my-app@1.0.0?arch=arm' -> 'pkg:generic/my-app'
    """
    if not purl_string:
        return None
    base = purl_string.split('?')
    base = base[0].split('@')
    return base[0]

def enrich_sbom(sbom_path, db_path, output_path):
    with open(sbom_path, 'r', encoding='utf-8') as f:
        sbom = json.load(f)
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # 1. Dynamically detect table structure
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall() if row[0] != 'sqlite_sequence']
    if not tables:
        print("[-] Error: No valid data tables found in purl2cpe.db.")
        return
    table_name = tables[0]
    print(f"[*] Successfully connected to database table: '{table_name}'")
    
    # 2. Dynamically detect table schema
    cursor.execute(f"PRAGMA table_info({table_name});")
    columns = [col[1] for col in cursor.fetchall()]
    has_purl = 'purl' in columns
    has_cpe = 'cpe' in columns
    
    if not (has_purl and has_cpe):
        print("[-] Error: Database schema missing standard 'purl' or 'cpe' fields.")
        return

    components = sbom.get('components', [])
    total_components = len(components)
    
    os_count = 0
    precise_mapped_count = 0
    fallback_count = 0
    
    print(f"[*] Processing all {total_components} components dynamically...")
    
    for comp in components:
        purl = comp.get('purl')
        if not purl:
            continue
            
        raw_version = comp.get('version', '*')
        version = clean_version(raw_version)
        
        # Scenario A: Native Debian OS packages remain unchanged to match Debian Security Feeds accurately
        if purl.startswith("pkg:deb/debian"):
            os_count += 1
            continue
            
        # Scenario B: Execute global automated CPE transformation for all non-OS third-party items
        purl_base = parse_purl_base(purl)
        
        # Secure prefix matching via SQLite indexing
        cursor.execute(f"SELECT cpe FROM {table_name} WHERE purl LIKE ? LIMIT 1", (f"{purl_base}%",))
        row = cursor.fetchone()
        
        if row and row[0]:
            db_cpe = row[0]
            cpe_parts = db_cpe.split(':')
            if len(cpe_parts) >= 5:
                # Dynamically extract official NVD vendor/product and inject the current accurate version string
                vendor = cpe_parts[3]
                product = cpe_parts[4]
                comp['cpe'] = f"cpe:2.3:a:{vendor}:{product}:{version}:*:*:*:*:*:*:*"
                precise_mapped_count += 1
                continue
        
        # Scenario C: Clean structural fallback to prevent arbitrary scanning false-positives
        purl_body = purl_base.replace("pkg:", "")
        body_parts = purl_body.split('/')
        
        if len(body_parts) >= 3:
            vendor = body_parts[-2]
            product = body_parts[-1]
        elif len(body_parts) == 2:
            vendor = body_parts[0]
            product = body_parts[1]
        else:
            vendor = "generic"
            product = body_parts[0]
            
        comp['cpe'] = f"cpe:2.3:a:{vendor}:{product}:{version}:*:*:*:*:*:*:*"
        fallback_count += 1
            
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(sbom, f, indent=2, ensure_ascii=False)
        
    conn.close()
    print(f"[+] Full-Scale Pipeline Execution Finished!")
    print(f"    - Total Components in SBOM   : {total_components}")
    print(f"    - Kept as Native Debian Feeds: {os_count}")
    print(f"    - NVD Precision-Mapped (DB)  : {precise_mapped_count}")
    print(f"    - Structured Fallback Mapped : {fallback_count}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 enrich_sbom.py <raw_sbom.json> <purl2cpe.db> <enriched_sbom.json>")
        sys.exit(1)
    enrich_sbom(sys.argv[1], sys.argv[2], sys.argv[3])
