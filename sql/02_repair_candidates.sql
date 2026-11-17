-- GitHub公開用の初回実行版。新規の検証用スキーマで番号順に実行。
-- 実行済み追補SQLから再構成。初回版全体のOracle実機通し実行は未確認。
-- SQLcl/SQL*Plus: リポジトリ直下から @sql/02_repair_candidates.sql
-- エラー時は停止。DDLで作成済みの表はROLLBACKしても残ります。
SET ECHO ON
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 240
SET PAGESIZE 100
SET DEFINE OFF
WHENEVER OSERROR EXIT FAILURE ROLLBACK
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK
SPOOL 02_repair_candidates.log
DECLARE
BEGIN
  IF USER <> 'SPATIAL_USER' OR SYS_CONTEXT('USERENV','CURRENT_SCHEMA') <> 'SPATIAL_USER' THEN
    RAISE_APPLICATION_ERROR(-20090,'Connect as SPATIAL_USER');
  END IF;
END;
/
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
  FOR r IN (SELECT c.COAST_ID, c.SOURCE_FILE, c.GEOM FROM COASTLINE_SOURCE c ORDER BY c.COAST_ID) LOOP
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


DECLARE
 n NUMBER;
BEGIN
 SELECT COUNT(*) INTO n FROM COASTLINE_REPAIR_CHECK
 WHERE REPAIR_STATUS NOT IN ('UNCHANGED_VALID','REPAIRED_VALID','SHORT_LINE_REVIEW','CANDIDATE_REVIEW');
 IF n<>0 THEN RAISE_APPLICATION_ERROR(-20096,'Unexpected repair failures; inspect candidate table'); END IF;
END;
/

SPOOL OFF
SET ECHO OFF
SET DEFINE ON
