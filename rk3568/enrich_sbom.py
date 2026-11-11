import json
import sqlite3
import sys

def enrich_sbom(sbom_path, db_path, output_path):
    with open(sbom_path, 'r', encoding='utf-8') as f:
        sbom = json.load(f)
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Automatically detect table names in the database
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall() if row[0] != 'sqlite_sequence']
    if not tables:
        print("[-] Error: No valid data tables found. Please check if purl2cpe.db is intact.")
        return
    table_name = tables[0]
    print(f"[*] Detected database table name: '{table_name}'")
    
    # Automatically detect columns of the table
    cursor.execute(f"PRAGMA table_info({table_name});")
    columns = [col[1] for col in cursor.fetchall()]
    print(f"[*] Table columns detected: {columns}")
    
    # Adaptive schema matching flags
    has_purl = 'purl' in columns
    has_cpe = 'cpe' in columns
    
    components = sbom.get('components', [])
    enriched_count = 0
    print(f"[*] Scanning {len(components)} components for precise CPE mapping...")
    
    for comp in components:
        purl = comp.get('purl')
        # Skip native debian system packages, focus on third-party libraries/binaries
        if purl and not purl.startswith("pkg:deb/debian"):
            purl_base = purl.split('@')[0] # Extract the base PURL without version suffix
            
            # Execute query based on the adaptive table schema
            if has_purl and has_cpe:
                cursor.execute(f"SELECT cpe FROM {table_name} WHERE purl LIKE ? LIMIT 1", (f"{purl_base}%",))
            else:
                # Fallback to general schema format
                cursor.execute(f"SELECT * FROM {table_name} WHERE {columns[0]} LIKE ? LIMIT 1", (f"{purl_base}%",))
                
            row = cursor.fetchone()
            if row:
                matched_cpe = row[0] if (has_purl and has_cpe) else row[1]
                version = comp.get('version', '*')
                
                # Dynamically substitute the template CPE version with current component version
                cpe_parts = matched_cpe.split(':')
                if len(cpe_parts) >= 5:
                    cpe_parts[5] = version
                    precise_cpe = ":".join(cpe_parts)
                    comp['cpe'] = precise_cpe
                    enriched_count += 1
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(sbom, f, indent=2, ensure_ascii=False)
        
    conn.close()
    print(f"[+] Enrichment finished! Successfully injected precise CPEs into {enriched_count} third-party components.")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 enrich_sbom.py <raw_sbom.json> <purl2cpe.db> <enriched_sbom.json>")
        sys.exit(1)
    enrich_sbom(sys.argv[1], sys.argv[2], sys.argv[3])
