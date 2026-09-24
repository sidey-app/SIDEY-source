import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
from character_five_provenance import verify_character_five_provenance


def read(path):
    return (ROOT / path).read_bytes()


class ApprovedContentTests(unittest.TestCase):
    def test_promoted_files_follow_selected_original_or_recorded_derivative(self):
        final = verify_character_five_provenance(read)
        promotion = json.loads(read('assets/v1/character-five-source.json'))
        unchanged = [item for item in promotion['files'] if 'derivative' not in item]
        for item in unchanged:
            self.assertFalse(item['destination'].startswith('assets/v1/characters/'))
            self.assertEqual(read(item['source']), read(item['destination']))

    def test_compact_revision_reproduces_all_frames_and_matches_canonical_and_web(self):
        directory = ROOT / 'docs/reviews/character-five'
        sys.path.insert(0, str(directory))
        try:
            spec = importlib.util.spec_from_file_location('compact_feet_v1', directory / 'build_compact_feet_v1.py')
            generator = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(generator)
            outputs, report, pairs = generator.build()
        finally:
            sys.path.remove(str(directory))
        generator.self_test(pairs)
        for path, encoded in outputs.items():
            self.assertEqual((generator.TARGET / path).read_bytes(), encoded, path)
        manifest = json.loads(read('assets/v1/manifest.json'))
        for sheet in report['sheets']:
            character = next(item for item in manifest['characters'] if item['id'] == sheet['character_id'])
            asset = character[sheet['sheet']]
            self.assertEqual(asset['sha256'], sheet['sha256'])
            self.assertEqual(read('assets/v1/' + asset['path']), outputs[sheet['path']])
            if sheet['sheet'] == 'base':
                self.assertEqual(read(f"website/public/assets/{character['web_directory']}/{character['id']}.png"), outputs[sheet['path']])

    def test_provenance_rejects_changed_generator_result_approval_and_canonical(self):
        for path in [
            'docs/reviews/character-five/build_compact_feet_v1.py',
            'docs/reviews/character-five-compact-feet-v1/pixel_shiba/base.png',
            'docs/reviews/character-five/approvals.json',
            'assets/v1/characters/pixel_shiba/base.png',
        ]:
            with self.subTest(path=path):
                with self.assertRaises(ValueError):
                    verify_character_five_provenance(lambda requested: read(requested) + (b' ' if requested == path else b''))

    def test_provenance_rejects_invented_user_approval_and_wrong_input(self):
        revision_path = 'docs/reviews/character-five-compact-feet-v1/revision.json'
        revision = json.loads(read(revision_path))
        revision['authorization']['new_pixels_explicitly_approved_by_user'] = True
        with self.assertRaisesRegex(ValueError, 'distinguish'):
            verify_character_five_provenance(lambda path: json.dumps(revision).encode() if path == revision_path else read(path))
        promotion_path = 'assets/v1/character-five-source.json'
        promotion = json.loads(read(promotion_path))
        promotion['files'][0]['derivative']['input']['sha256'] = '0' * 64
        with self.assertRaisesRegex(ValueError, 'input'):
            verify_character_five_provenance(lambda path: json.dumps(promotion).encode() if path == promotion_path else read(path))

    def test_prior_reviewed_snapshots_without_derivatives_remain_verifiable(self):
        path = 'assets/v1/character-five-source.json'
        promotion = json.loads(read(path))
        legacy = {}
        for item in promotion['files']:
            item.pop('derivative', None)
            legacy[item['destination']] = read(item['source'])
        legacy[path] = json.dumps(promotion).encode()
        final = verify_character_five_provenance(lambda path: legacy[path] if path in legacy else read(path))
        self.assertTrue(all('compact-feet' not in item['source'] for item in final))
