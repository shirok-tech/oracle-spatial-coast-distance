-- SQLcl / SQL*Plus: @04_coastline_repair_candidates.sql
-- SPATIAL_USER専用の新しいセッションで実行してください。
-- 実DBでは未実行。COASTLINE_REPAIR_CHECKを新規作成し、補正候補を保存します。
-- 元のCOASTLINE / COASTLINE_WGS84 / 距離結果 / ビューは更新しません。
-- LIGHTSの空間メタデータ・空間索引は、存在しない場合だけ追加します。
-- DDLを含むため、同じセッションに別作業の未確定更新を残さないでください。
-- 同名の検証表がある場合は停止します。既存の検証記録は削除しません。
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 240
SET PAGESIZE 500
SET TRIMSPOOL ON
SET DEFINE OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SPOOL 04_coastline_repair_candidates.log

PROMPT === 1. Preconditions ===
DECLARE
  n NUMBER;
BEGIN
  IF USER <> 'SPATIAL_USER'
     OR SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') <> 'SPATIAL_USER' THEN
    RAISE_APPLICATION_ERROR(-20001, 'Connect as SPATIAL_USER with the same current schema');
  END IF;
  SELECT COUNT(*) INTO n FROM USER_OBJECTS
  WHERE OBJECT_NAME = 'COASTLINE_REPAIR_CHECK';
  IF n > 0 THEN
    RAISE_APPLICATION_ERROR(-20002, 'COASTLINE_REPAIR_CHECK already exists. Preserve the earlier run');
  END IF;
  SELECT COUNT(*) INTO n FROM COASTLINE;
  IF n <> 4991 THEN
    RAISE_APPLICATION_ERROR(-20003, 'Expected 4991 coastline records. Check source data');
  END IF;
  SELECT COUNT(*) INTO n FROM COASTLINE c
  WHERE c.GEOM IS NULL OR NVL(c.GEOM.SDO_GTYPE, -1) <> 2002
     OR NVL(c.GEOM.SDO_SRID, -1) <> 4326;
  IF n > 0 THEN
    RAISE_APPLICATION_ERROR(-20004, 'Expected non-null 2D lines with SRID 4326');
  END IF;
END;
/

PROMPT === 2. Candidate table (original coastline remains unchanged) ===
CREATE TABLE COASTLINE_REPAIR_CHECK (
  COAST_ID NUMBER PRIMARY KEY,
  SOURCE_FILE VARCHAR2(1024),
  BEFORE_RESULT VARCHAR2(4000),
  AFTER_RESULT VARCHAR2(4000),
  BEFORE_VERTICES NUMBER,
  AFTER_VERTICES NUMBER,
  REPAIR_STATUS VARCHAR2(40),
  ERROR_TEXT VARCHAR2(4000),
  CANDIDATE_GEOM MDSYS.SDO_GEOMETRY
);

DECLARE
  g MDSYS.SDO_GEOMETRY;
  v_before_result VARCHAR2(4000);
  v_after_result VARCHAR2(4000);
  v_before_vertices NUMBER;
  v_after_vertices NUMBER;
  v_repair_status VARCHAR2(40);
  v_error_text VARCHAR2(4000);
  n NUMBER := 0;
BEGIN
  FOR r IN (SELECT c.COAST_ID, c.SOURCE_FILE, c.GEOM FROM COASTLINE c ORDER BY c.COAST_ID) LOOP
    g := NULL;
    v_before_result := NULL;
    v_after_result := NULL;
    v_before_vertices := NULL;
    v_after_vertices := NULL;
    v_repair_status := 'REVIEW_REQUIRED';
    v_error_text := NULL;
    BEGIN
      v_before_vertices := SDO_UTIL.GETNUMVERTICES(r.GEOM);
      v_before_result := NVL(SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT(r.GEOM, 0.05), 'NULL_GEOMETRY');
      IF v_before_result = 'TRUE' THEN
        g := r.GEOM;
        v_after_result := v_before_result;
        v_after_vertices := v_before_vertices;
        v_repair_status := 'UNCHANGED_VALID';
      ELSIF REGEXP_SUBSTR(v_before_result, '^[^ ]+') = '13356' THEN
        IF v_before_vertices <= 2 THEN
          -- 2頂点を1頂点にすると線として成立しないため、別途判断します。
          v_repair_status := 'SHORT_LINE_REVIEW';
          v_after_result := 'NOT_ATTEMPTED';
        ELSE
          g := SDO_UTIL.REMOVE_DUPLICATE_VERTICES(r.GEOM, 0.05);
          IF g IS NULL THEN
            v_repair_status := 'NULL_CANDIDATE';
            v_after_result := 'NULL_GEOMETRY';
          ELSE
            v_after_vertices := SDO_UTIL.GETNUMVERTICES(g);
            v_after_result := NVL(SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT(g, 0.05), 'NULL_GEOMETRY');
            IF v_after_result = 'TRUE' AND g.SDO_GTYPE = 2002
               AND g.SDO_SRID = 4326 AND v_after_vertices >= 2 THEN
              v_repair_status := 'REPAIRED_VALID';
            ELSE
              v_repair_status := 'CANDIDATE_REVIEW';
            END IF;
          END IF;
        END IF;
      ELSE
        v_repair_status := 'OTHER_ERROR_REVIEW';
        v_after_result := 'NOT_ATTEMPTED';
      END IF;
    EXCEPTION
      WHEN OTHERS THEN
        v_repair_status := 'FUNCTION_ERROR';
        v_error_text := SUBSTR(SQLERRM, 1, 4000);
    END;
    INSERT INTO COASTLINE_REPAIR_CHECK
      (COAST_ID, SOURCE_FILE, BEFORE_RESULT, AFTER_RESULT,
       BEFORE_VERTICES, AFTER_VERTICES, REPAIR_STATUS, ERROR_TEXT, CANDIDATE_GEOM)
    VALUES
      (r.COAST_ID, r.SOURCE_FILE, v_before_result, v_after_result,
       v_before_vertices, v_after_vertices, v_repair_status, v_error_text, g);
    n := n + 1;
  END LOOP;
  IF n <> 4991 THEN
    RAISE_APPLICATION_ERROR(-20005, 'Unexpected candidate count');
  END IF;
  COMMIT;
  DBMS_OUTPUT.PUT_LINE('Candidate records saved: ' || n);
END;
/

PROMPT === 3. Candidate summary and unresolved records ===
SELECT REPAIR_STATUS, COUNT(*) AS GEOMETRY_COUNT,
       MIN(BEFORE_VERTICES) AS MIN_VERTICES,
       MAX(BEFORE_VERTICES) AS MAX_VERTICES
FROM COASTLINE_REPAIR_CHECK
GROUP BY REPAIR_STATUS ORDER BY REPAIR_STATUS;

SELECT COUNT(*) AS TOTAL_COUNT,
       SUM(CASE WHEN REPAIR_STATUS IN ('UNCHANGED_VALID','REPAIRED_VALID')
                THEN 1 ELSE 0 END) AS VALID_LINE_CANDIDATES,
       SUM(CASE WHEN REPAIR_STATUS NOT IN ('UNCHANGED_VALID','REPAIRED_VALID')
                THEN 1 ELSE 0 END) AS REVIEW_REQUIRED_COUNT
FROM COASTLINE_REPAIR_CHECK;

SELECT COAST_ID, SOURCE_FILE, BEFORE_VERTICES, AFTER_VERTICES,
       REPAIR_STATUS, AFTER_RESULT, ERROR_TEXT
FROM COASTLINE_REPAIR_CHECK
WHERE REPAIR_STATUS NOT IN ('UNCHANGED_VALID','REPAIRED_VALID')
ORDER BY COAST_ID;

PROMPT === 4. Endpoints of short lines (original coordinates) ===
SELECT c.COAST_ID, v.ID AS VERTEX_NO, v.X AS LONGITUDE, v.Y AS LATITUDE
FROM COASTLINE c
JOIN COASTLINE_REPAIR_CHECK r ON r.COAST_ID = c.COAST_ID,
     TABLE(SDO_UTIL.GETVERTICES(c.GEOM)) v
WHERE r.REPAIR_STATUS = 'SHORT_LINE_REVIEW'
ORDER BY c.COAST_ID, v.ID;

PROMPT === 5. Current nearest-line matches by repair status ===
SELECT NVL(r.REPAIR_STATUS, 'MISSING_COAST_ID') AS REPAIR_STATUS,
       COUNT(*) AS LIGHT_COUNT
FROM LIGHT_COAST_METRICS m
LEFT JOIN COASTLINE_REPAIR_CHECK r ON r.COAST_ID = m.NEAREST_COAST_ID
GROUP BY r.REPAIR_STATUS ORDER BY r.REPAIR_STATUS;

PROMPT === 6. Current matches to source type other than coastline ===
SELECT m.ASSET_ID, l.LOCATION_TEXT, m.NEAREST_COAST_ID,
       ROUND(m.COAST_DISTANCE_M, 3) AS DISTANCE_M,
       c.COAST_TYPE, c.SOURCE_FILE
FROM LIGHT_COAST_METRICS m
JOIN LIGHTS l ON l.ASSET_ID = m.ASSET_ID
LEFT JOIN COASTLINE_WGS84 c ON c.COAST_ID = m.NEAREST_COAST_ID
WHERE c.COAST_TYPE IS NULL OR c.COAST_TYPE <> '海岸線'
ORDER BY m.ASSET_ID;

PROMPT === 7. Complete LIGHTS metadata and spatial index if absent ===
DECLARE
  n NUMBER;
  n_srid NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM LIGHTS l
  WHERE l.GEOM IS NULL OR NVL(l.GEOM.SDO_GTYPE, -1) <> 2001
     OR NVL(l.GEOM.SDO_SRID, -1) <> 4326
     OR NVL(SDO_GEOM.VALIDATE_GEOMETRY_WITH_CONTEXT(l.GEOM, 0.05), 'INVALID') <> 'TRUE';
  IF n > 0 THEN
    RAISE_APPLICATION_ERROR(-20006, 'LIGHTS geometry validation failed');
  END IF;
  SELECT COUNT(*), MAX(SRID) INTO n, n_srid FROM USER_SDO_GEOM_METADATA
  WHERE TABLE_NAME = 'LIGHTS' AND COLUMN_NAME = 'GEOM';
  IF n = 0 THEN
    INSERT INTO USER_SDO_GEOM_METADATA(TABLE_NAME, COLUMN_NAME, DIMINFO, SRID)
    VALUES ('LIGHTS', 'GEOM', MDSYS.SDO_DIM_ARRAY(
      MDSYS.SDO_DIM_ELEMENT('LONGITUDE', -180, 180, 0.05),
      MDSYS.SDO_DIM_ELEMENT('LATITUDE', -90, 90, 0.05)), 4326);
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('LIGHTS metadata added');
  ELSIF n <> 1 OR NVL(n_srid, -1) <> 4326 THEN
    RAISE_APPLICATION_ERROR(-20007, 'Unexpected existing LIGHTS metadata');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Existing LIGHTS metadata retained');
  END IF;
  -- 別名の空間索引がある場合も重複作成を避けます。
  SELECT COUNT(*) INTO n FROM USER_INDEXES i
  JOIN USER_IND_COLUMNS c ON c.INDEX_NAME = i.INDEX_NAME
  WHERE i.TABLE_NAME = 'LIGHTS' AND c.COLUMN_NAME = 'GEOM'
    AND i.ITYP_OWNER = 'MDSYS' AND i.ITYP_NAME LIKE 'SPATIAL_INDEX%';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE INDEX LIGHTS_SIDX ON LIGHTS(GEOM) INDEXTYPE IS MDSYS.SPATIAL_INDEX_V2';
    DBMS_OUTPUT.PUT_LINE('LIGHTS_SIDX created');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Existing LIGHTS spatial index retained; check status below');
  END IF;
END;
/

SELECT m.TABLE_NAME, m.COLUMN_NAME, m.SRID,
       d.SDO_DIMNAME AS DIM_NAME, d.SDO_LB AS LOWER_BOUND,
       d.SDO_UB AS UPPER_BOUND, d.SDO_TOLERANCE AS TOLERANCE
FROM USER_SDO_GEOM_METADATA m, TABLE(m.DIMINFO) d
WHERE m.TABLE_NAME IN ('LIGHTS','COASTLINE')
ORDER BY m.TABLE_NAME, d.SDO_DIMNAME;

SELECT INDEX_NAME, TABLE_NAME, ITYP_NAME, STATUS, DOMIDX_STATUS, DOMIDX_OPSTATUS
FROM USER_INDEXES
WHERE TABLE_NAME IN ('LIGHTS','COASTLINE') AND ITYP_OWNER = 'MDSYS'
ORDER BY TABLE_NAME, INDEX_NAME;

PROMPT === Candidate review complete; coastline and distance results were not replaced ===
PROMPT Return this log. Review unresolved candidates before applying repairs or recalculating.
SPOOL OFF
SET ECHO OFF
WHENEVER SQLERROR CONTINUE NONE
