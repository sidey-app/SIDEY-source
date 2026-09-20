from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ROOT / '.github' / 'workflows'


class WorkflowContractTests(unittest.TestCase):
    def read(self, name):
        return (WORKFLOWS / name).read_text(encoding='utf-8')

    def test_workflow_and_job_names_describe_their_responsibilities(self):
        workflow_names = {
            'ci.yml': 'name: SIDEY CI',
            'macos-build-and-tests.yml': (
                'name: SIDEY CI (macOS build and tests)'
            ),
            'windows-build-and-tests.yml': (
                'name: SIDEY CI (Windows build and tests)'
            ),
            'release-metadata-checks.yml': (
                'name: SIDEY CI (release metadata checks)'
            ),
            'website-deployment.yml': (
                'name: SIDEY Website deployment'
            ),
            'windows-release.yml': 'name: SIDEY Windows release',
        }
        for filename, name in workflow_names.items():
            with self.subTest(filename=filename):
                self.assertEqual(self.read(filename).splitlines()[0], name)

        ci = self.read('ci.yml')
        for name in (
            'Select required checks',
            'Repository checks',
            'macOS build and tests',
            'Windows build and tests',
            'Website build and tests',
            'Required checks',
        ):
            with self.subTest(job=name):
                self.assertIn(f'name: {name}', ci)

        website = self.read('website-deployment.yml')
        self.assertIn('name: Build and test website', website)
        self.assertIn('name: Deploy to GitHub Pages', website)
        self.assertIn('Publish tested website to public gh-pages branch', website)

        release = self.read('windows-release.yml')
        self.assertIn('name: Build release candidate', release)
        self.assertIn('name: Publish GitHub release', release)
        self.assertIn('name: Update release website', release)

    def test_ci_is_the_automatic_shared_validation_entrypoint(self):
        validation = self.read('ci.yml')
        self.assertIn(
            'python3 scripts/skills/validate_contributor_architecture.py',
            validation,
        )
        self.assertIn(
            'python3 -m unittest discover -s '
            'scripts/skills/release-notes/tests',
            validation,
        )
        self.assertNotIn(
            '--require-windows-instruction-foundation',
            validation,
        )
        self.assertIn(
            'python -X utf8 '
            './windows/tools/sync_product_assets.py --check',
            validation,
        )
        self.assertIn('Run Windows app smoke', validation)
        smoke_step = validation.split(
            '- name: Run Windows app smoke',
            1,
        )[1].split('\n      - name:', 1)[0]
        self.assertIn("if: github.event_name == 'push'", smoke_step)
        self.assertIn(
            'powershell.exe -NoProfile -NonInteractive '
            '-ExecutionPolicy Bypass -File '
            './scripts/windows/tests/'
            'Test-PublishedApplicationTimeouts.ps1',
            validation,
        )
        self.assertIn('name: Required checks', validation)
        self.assertIn(
            'run-name: "SIDEY CI | ${{ github.event_name }} | '
            '${{ github.ref_name }}"',
            validation,
        )
        for name in ('release-metadata-checks.yml',):
            with self.subTest(workflow=name):
                workflow = self.read(name)
                self.assertIn('  workflow_dispatch:', workflow)
                self.assertNotIn('  pull_request:', workflow)
                self.assertNotIn('  push:', workflow)

    def test_ci_revalidates_edited_pr_bodies_without_label_events(self):
        workflow = self.read('ci.yml')
        self.assertIn(
            'types: [opened, synchronize, reopened, edited]',
            workflow,
        )
        self.assertNotIn('labeled', workflow)
        self.assertNotIn('unlabeled', workflow)
        self.assertIn("github.event.pull_request.state == 'open'", workflow)

    def test_website_deployment_reuses_the_tested_build(self):
        workflow = self.read('website-deployment.yml')
        validation = self.read('ci.yml')
        self.assertNotIn('  pull_request:', workflow)
        self.assertEqual(
            workflow.count('pnpm install --frozen-lockfile'),
            1,
        )
        self.assertEqual(workflow.count('pnpm test'), 1)
        pages_tests = 'python3 -m unittest discover -s scripts/pages/tests'
        self.assertIn(pages_tests, workflow)
        self.assertIn(pages_tests, validation)
        self.assertIn(
            'python3 ./scripts/pages/prepare_release_metadata.py',
            workflow,
        )
        old_script = './scripts/website/prepare-release-metadata.ps1'
        self.assertNotIn(old_script, workflow)
        self.assertNotIn(old_script, validation)
        self.assertIn('name: Upload tested website build', workflow)
        self.assertIn('name: Download tested website build', workflow)
        self.assertIn('actions/create-github-app-token@v2', workflow)
        self.assertIn('scripts/publication/validate_public_tree.py', workflow)
        self.assertIn('scripts/publication/compliance-source-assets.json', workflow)
        self.assertIn('$expectedAssetNames = @($installerName) + $complianceAssetNames', workflow)
        self.assertIn('repository: ${{ env.PUBLIC_REPOSITORY }}', workflow)
        self.assertNotIn('actions/deploy-pages', workflow)

    def test_public_checkout_excludes_backend_sources(self):
        private_paths = (
            'supabase',
            'services/app-store-verifier',
            'scripts/supabase',
            'scripts/download-metrics',
            'scripts/configure_supabase_staging.sh',
            '.github/workflows/database.yml',
            '.github/workflows/download-metrics.yml',
        )
        # Ignore leftover local build caches after the split, but
        # reject new untracked source too. Deleted files may still
        # appear in the index.
        candidates = subprocess.check_output(
            [
                'git',
                '-C',
                str(ROOT),
                'ls-files',
                '-z',
                '--cached',
                '--others',
                '--exclude-standard',
            ]
        ).decode().split('\0')
        unexpected = [
            path
            for path in candidates
            if path
            and (ROOT / path).exists()
            and any(
                path == owned or path.startswith(owned + '/')
                for owned in private_paths
            )
        ]
        self.assertEqual(
            unexpected,
            [],
            'Backend implementation belongs in sidey-app/sidey-backend',
        )
        validation = self.read('ci.yml')
        self.assertNotIn('  database:', validation)
        self.assertNotIn('  server:', validation)
        self.assertIn(
            'needs: [scope, shared, macos, windows, web]',
            validation,
        )

    def test_website_deployment_excludes_contributor_only_files(self):
        workflow = self.read('website-deployment.yml')
        self.assertNotIn("- 'website/**'", workflow)
        self.assertNotIn('website/AGENTS.md', workflow)
        self.assertIn("- 'website/src/**'", workflow)
        self.assertIn("- 'website/public/**'", workflow)
        self.assertIn("- 'scripts/publication/**'", workflow)
        self.assertNotIn("- 'scripts/validate_pixel_assets.py'", workflow)


if __name__ == '__main__':
    unittest.main()
