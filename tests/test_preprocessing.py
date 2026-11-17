"""CLI tests with small synthetic inputs. No network or Oracle connection."""
import csv
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]

class PreprocessingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.work = Path(self.tmp.name)

    def run_cli(self, script, *args, success=True):
        p = subprocess.run([sys.executable, str(ROOT / script), *map(str, args)],
                           cwd=self.work, capture_output=True, text=True)
        if success:
            self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        else:
            self.assertNotEqual(p.returncode, 0)
        return p

    def test_csv_filter_id_and_rejected_coordinate(self):
        source = self.work / 'lights.csv'
        source.write_text('事務所名,路線名,設置位置,管理番号,照明灯種別,緯度,経度\n'
                          '下田,道路A,河津町,A,LED,34.7,138.9\n'
                          '下田,道路B,下田市,B,,34.68,138.95\n'
                          '下田,道路C,下田市,C,LED,nan,138.95\n', encoding='cp932')
        out = self.work / 'lights_out.csv'
        self.run_cli('prepare_lights.py', source, '--output', out)
        with out.open(encoding='utf-8-sig', newline='') as f:
            rows = list(csv.DictReader(f))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['SOURCE_ROW'], '2')
        self.assertEqual(rows[0]['ASSET_ID'], 'SZ20231004-000002')
        audit = json.loads(out.with_suffix('.audit.json').read_text())
        self.assertEqual(audit['rejected_rows'], 1)
        self.assertEqual(audit['missing_light_type'], 1)

    def test_reject_modified_english_headers(self):
        src=self.work/'english.csv'
        src.write_text('ASSET_ID,LATITUDE,LONGITUDE\nx,34.68,138.95\n')
        self.run_cli('prepare_lights.py',src,success=False)

    def test_nested_zip_and_existing_output(self):
        inner=io.BytesIO()
        with ZipFile(inner,'w') as z:
            z.writestr('FG-GML-523807-Cstline-20261001-0001.xml','<root/>')
            z.writestr('metadata.xml','<root/>')
        src=self.work/'outer.zip'
        with ZipFile(src,'w') as z: z.writestr('mesh.zip',inner.getvalue())
        out=self.work/'unpacked'
        self.run_cli('unpack_gsi_zip.py',src,'--output',out)
        self.assertEqual(len(list(out.rglob('*.xml'))),2)
        self.run_cli('unpack_gsi_zip.py',src,'--output',out,success=False)

    def test_reject_nested_zip_parent_directory(self):
        inner = io.BytesIO()
        name = 'FG-GML-523807-Cstline-20261001-0001.xml'
        with ZipFile(inner, 'w') as z:
            z.writestr(name, '<root/>')
        src = self.work / 'outer.zip'
        with ZipFile(src, 'w') as z:
            z.writestr('...zip', inner.getvalue())
        out = self.work / 'unpacked'
        self.run_cli('unpack_gsi_zip.py', src, '--output', out, success=False)
        self.assertFalse((self.work / name).exists())
        self.assertFalse(out.exists())

    def make_gml(self, srs='fguuid:jgd2024.bl', dimension='2'):
        folder=self.work/'gml'; folder.mkdir()
        (folder/'coast.xml').write_text(f'''<Dataset xmlns:gml="http://www.opengis.net/gml/3.2">
<Cstline><fid>coast-1</fid><type>海岸線</type><loc>
<gml:Curve srsName="{srs}" srsDimension="{dimension}"><gml:segments>
<gml:LineStringSegment><gml:posList>34.68 138.95 34.68 138.95 34.69 138.96</gml:posList></gml:LineStringSegment>
<gml:LineStringSegment><gml:posList>34.70 138.97 34.71 138.98</gml:posList></gml:LineStringSegment>
</gml:segments></gml:Curve></loc></Cstline>
<WStrL><loc/></WStrL></Dataset>''',encoding='utf-8')
        return folder

    def test_gml_axis_order_parts_and_duplicate_vertex(self):
        folder=self.make_gml(); out=self.work/'coast.geojson'
        self.run_cli('convert_gsi_coastline.py',folder,'--output',out)
        fs=json.loads(out.read_text())['features']
        self.assertEqual(len(fs),2)
        self.assertEqual(len(fs[0]['geometry']['coordinates']),2)
        self.assertAlmostEqual(fs[0]['geometry']['coordinates'][0][0],138.95,places=5)
        self.assertAlmostEqual(fs[0]['geometry']['coordinates'][0][1],34.68,places=5)
        self.assertEqual([x['properties']['PART_NO'] for x in fs],[1,2])
        self.assertEqual(json.loads(out.with_suffix('.manifest.json').read_text())['removed_consecutive_duplicate_points'],1)

    def test_reject_unknown_crs(self):
        p=self.run_cli('convert_gsi_coastline.py',self.make_gml(srs='unknown'),success=False)
        self.assertIn('未対応/不明な測地系',p.stderr)

    def test_reject_3d(self):
        p=self.run_cli('convert_gsi_coastline.py',self.make_gml(dimension='3'),success=False)
        self.assertIn('3D座標には対応していません',p.stderr)

if __name__ == '__main__':
    unittest.main()
