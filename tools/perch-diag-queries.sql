-- perch-diag-queries.sql — the database half of the Perch diagnostics.
--
-- perch-diag-appliance.sh runs this automatically. Run it by hand only if the
-- script reported SKIPPED for section 10 (external database, or the password
-- could not be read):
--
--   /opt/morpheus/embedded/mysql/bin/mysql -u morpheus -h 127.0.0.1 -p morpheus \
--     --force --table < perch-diag-queries.sql > /tmp/perch-diag-db.txt 2>&1
--
-- -h 127.0.0.1 matters: "localhost" uses the unix socket and is refused.
-- --force matters: a query against a table your Morpheus lacks should not stop
-- the rest. Those errors are themselves a finding — send them.
--
-- Read-only. Selects no credential column.

SELECT '=== A. MySQL version ===' AS s;
SELECT VERSION() AS mysql_version, DATABASE() AS db;

SELECT '=== B. Which tables Perch depends on exist here? ===' AS s;
SELECT t.n AS expected_table,
       CASE WHEN i.TABLE_NAME IS NULL THEN 'ABSENT' ELSE 'present' END AS state,
       COALESCE(i.TABLE_ROWS, 0) AS approx_rows
FROM (
  SELECT 'compute_zone' n UNION ALL SELECT 'compute_zone_type' UNION ALL
  SELECT 'compute_server' UNION ALL SELECT 'compute_server_type' UNION ALL
  SELECT 'compute_server_interface' UNION ALL
  SELECT 'compute_server_compute_server_interface' UNION ALL
  SELECT 'network' UNION ALL SELECT 'network_type' UNION ALL
  SELECT 'network_router' UNION ALL SELECT 'network_router_type' UNION ALL
  SELECT 'network_router_interface' UNION ALL SELECT 'network_route' UNION ALL
  SELECT 'network_router_network_route' UNION ALL SELECT 'security_group' UNION ALL
  SELECT 'security_group_rule' UNION ALL SELECT 'compute_server_security_group' UNION ALL
  SELECT 'container' UNION ALL SELECT 'container_type' UNION ALL SELECT 'service' UNION ALL
  SELECT 'monitor_check' UNION ALL SELECT 'audit_log' UNION ALL SELECT 'user' UNION ALL
  SELECT 'backup' UNION ALL SELECT 'backup_result' UNION ALL
  SELECT 'security_scan' UNION ALL SELECT 'security_scan_item' UNION ALL
  SELECT 'datastore' UNION ALL SELECT 'storage_volume' UNION ALL
  SELECT 'compute_server_storage_volume' UNION ALL SELECT 'compute_device' UNION ALL
  SELECT 'compute_device_type' UNION ALL SELECT 'network_server' UNION ALL
  SELECT 'network_switch' UNION ALL SELECT 'compute_zone_pool'
) t
LEFT JOIN information_schema.TABLES i
       ON i.TABLE_SCHEMA = DATABASE() AND i.TABLE_NAME = t.n
ORDER BY state, expected_table;

SELECT '=== C. Columns Perch guards on conditionally ===' AS s;
-- Perch checks these at runtime rather than assuming. A column missing here is
-- expected behaviour, not a bug — but the list tells us which guard fired.
SELECT c.TABLE_NAME, c.COLUMN_NAME, c.DATA_TYPE
FROM   information_schema.COLUMNS c
WHERE  c.TABLE_SCHEMA = DATABASE()
  AND (
       (c.TABLE_NAME IN ('compute_server','network_router','container','security_group',
                         'compute_zone','compute_device') AND c.COLUMN_NAME='deleted')
    OR (c.TABLE_NAME='compute_server_interface'
        AND c.COLUMN_NAME IN ('mac_address','network_id','ip_address','server_id'))
    OR (c.TABLE_NAME='backup' AND c.COLUMN_NAME IN ('server_id','compute_server_id'))
    OR (c.TABLE_NAME='monitor_check'
        AND c.COLUMN_NAME IN ('server_id','container_id','last_check_status'))
    OR (c.TABLE_NAME='network' AND c.COLUMN_NAME IN ('type_id','router_id','parent_network_id'))
    OR (c.TABLE_NAME='network_router' AND c.COLUMN_NAME IN ('type_id','router_type'))
    OR (c.TABLE_NAME='network_router_interface' AND c.COLUMN_NAME='ip_address')
    OR (c.TABLE_NAME='compute_device' AND c.COLUMN_NAME IN ('status','ref_type','ref_id','type_id'))
  )
ORDER BY c.TABLE_NAME, c.COLUMN_NAME;

SELECT '=== D. Scale — Perch is verified at 11 servers / 5 networks / 1 cloud ===' AS s;
SELECT (SELECT COUNT(*) FROM compute_zone)             AS clouds,
       (SELECT COUNT(*) FROM compute_server)           AS servers,
       (SELECT COUNT(*) FROM network)                  AS networks,
       (SELECT COUNT(*) FROM compute_server_interface) AS interfaces,
       (SELECT COUNT(*) FROM compute_server_interface
         WHERE network_id IS NOT NULL)                 AS ifaces_with_network,
       (SELECT COUNT(*) FROM network_router)           AS routers,
       (SELECT COUNT(*) FROM container)                AS containers;

SELECT '=== E. Cloud types — Perch is verified against ONE (standard/Private Cloud) ===' AS s;
SELECT zt.code, zt.name, COUNT(z.id) AS clouds
FROM compute_zone z JOIN compute_zone_type zt ON zt.id=z.zone_type_id
GROUP BY zt.code, zt.name ORDER BY clouds DESC;

SELECT '=== F. Server types — drives host-vs-VM and the icon glyph ===' AS s;
SELECT cst.code, cst.name, COUNT(cs.id) AS servers
FROM compute_server cs JOIN compute_server_type cst ON cst.id=cs.compute_server_type_id
GROUP BY cst.code, cst.name ORDER BY servers DESC;

SELECT '=== G. Network types — drives the network glyph ===' AS s;
SELECT nt.code, nt.name, COUNT(n.id) AS networks
FROM network n JOIN network_type nt ON nt.id=n.type_id
GROUP BY nt.code, nt.name ORDER BY networks DESC;

SELECT '=== H. Router types ===' AS s;
SELECT nrt.code, nrt.name, COUNT(nr.id) AS routers
FROM network_router nr JOIN network_router_type nrt ON nrt.id=nr.type_id
GROUP BY nrt.code, nrt.name ORDER BY routers DESC;

SELECT '=== I. Per-layer data availability — an empty layer with 0 rows is CORRECT ===' AS s;
SELECT 'security_group' AS layer, COUNT(*) AS rows_found FROM security_group
UNION ALL SELECT 'monitor_check',  COUNT(*) FROM monitor_check
UNION ALL SELECT 'backup',         COUNT(*) FROM backup
UNION ALL SELECT 'security_scan',  COUNT(*) FROM security_scan
UNION ALL SELECT 'audit_log(30d)', COUNT(*) FROM audit_log
          WHERE date_created > DATE_SUB(NOW(), INTERVAL 30 DAY)
UNION ALL SELECT 'datastore',      COUNT(*) FROM datastore
UNION ALL SELECT 'storage_volume', COUNT(*) FROM storage_volume
UNION ALL SELECT 'compute_device', COUNT(*) FROM compute_device;

SELECT '=== J. Host -> guest mapping — drives the server tab ===' AS s;
SELECT p.id AS host_id, p.name AS host, COUNT(c.id) AS guests
FROM compute_server c JOIN compute_server p ON p.id=c.parent_server_id
GROUP BY p.id, p.name ORDER BY guests DESC LIMIT 30;

SELECT '=== K. Hardware strings — trailing-newline check ===' AS s;
-- Every value on the reference appliance ends 0x0A, and MySQL TRIM() does not
-- strip it. If ending_in_newline is 0 on yours, that artifact is environment-
-- specific and worth telling us about.
SELECT COUNT(*) AS with_vendor,
       SUM(RIGHT(hardware_product_vendor,1)=CHAR(10)) AS ending_in_newline
FROM compute_server WHERE hardware_product_vendor IS NOT NULL;

SELECT '=== L. Recent Perch report runs ===' AS s;
SELECT id, status, date_created FROM report_result ORDER BY id DESC LIMIT 10;

SELECT '=== M. Multi-tenancy — Perch does NOT filter by tenant ===' AS s;
-- Perch reads the database directly and bypasses Morpheus RBAC.
-- getMasterOnly() is the only control. If this shows more than one account with
-- infrastructure, read docs/LIMITATIONS.md before exposing Perch to sub-tenants.
SELECT a.id, a.name, COUNT(z.id) AS clouds
FROM account a LEFT JOIN compute_zone z ON z.account_id=a.id
GROUP BY a.id, a.name ORDER BY clouds DESC;

SELECT '=== queries complete ===' AS s;
