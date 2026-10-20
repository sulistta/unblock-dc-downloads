#!/usr/bin/env python3
"""Exercise the real shell installer with offline downloads and a fake CLI."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

class Installer(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root/'home'; self.home.mkdir()
        self.bin = self.root/'commands'; self.bin.mkdir()
        self.download = self.root/'package.tar.gz'
        self.files = {'unblock-2': b'#!/bin/sh\nexit "${FIXTURE_EXIT:-0}"\n','runtime/openvpn': b'fixture runtime','README.md':b'readme','LICENSE':b'license'}
        for n in ['NOTICE','OpenVPN','OpenSSL','libcap-ng']: self.files['runtime/licenses/'+n+'.txt'] = b'license'
        self.archive()
        self.manifest = {'schema':2,'version':'0.7.0','linux_x86_64':{'url':'https://github.com/sulistta/unblock-dc-downloads/releases/download/v0.7.0/unblock-2-linux-x86_64.tar.gz','sha256':hashlib.sha256(self.download.read_bytes()).hexdigest()}}
        self.script('pkexec','exit 0')
        self.script('systemctl','exit 0')
        self.script('curl','''while [ "$#" -gt 0 ]; do case "$1" in --output) out=$2; shift 2;; https:*) url=$1; shift;; *) shift;; esac; done
case "$url" in */latest.json) cp "$FIXTURE_MANIFEST" "$out";; *.tar.gz) cp "$FIXTURE_ARCHIVE" "$out";; *) exit 1;; esac''')
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin)+':'+os.environ['PATH'], FIXTURE_MANIFEST=str(self.root/'latest.json'), FIXTURE_ARCHIVE=str(self.download), TMPDIR=str(self.root))
    def tearDown(self): self.temp.cleanup()
    def script(self,name,body):
        p=self.bin/name;p.write_text('#!/bin/sh\n'+body+'\n');p.chmod(0o755)
    def archive(self,link=False):
        with tarfile.open(self.download,'w:gz') as tar:
            for name,data in self.files.items():
                entry=tarfile.TarInfo(name);entry.mode=0o755;entry.size=len(data)
                if link and name=='runtime/openvpn': entry.type=tarfile.SYMTYPE;entry.linkname='/tmp/outside';entry.size=0
                tar.addfile(entry,io.BytesIO(data) if entry.size else None)
    def run_installer(self,ok=True):
        (self.root/'latest.json').write_text(json.dumps(self.manifest,indent=2)+'\n')
        run=subprocess.run(['bash',str(Path(__file__).parents[1]/'install.sh')],env=self.env,text=True,capture_output=True)
        self.assertEqual(run.returncode==0,ok,run.stdout+run.stderr)
        self.assertEqual(list(self.root.glob('unblock-dc-install.*')),[])
        return run
    def test_install_update_and_runtime_cleanup(self):
        self.run_installer();cli=self.home/'.local/bin/unblock-2';self.assertTrue(cli.is_symlink())
        previous=cli.resolve().parent;self.assertTrue((previous/'runtime/openvpn').is_file())
        self.run_installer();self.assertNotEqual(previous,cli.resolve().parent);self.assertFalse(previous.exists())
    def test_corrupt_download_does_not_change_existing_cli(self):
        self.run_installer();cli=self.home/'.local/bin/unblock-2';previous=cli.resolve()
        self.manifest['linux_x86_64']['sha256']='0'*64;self.run_installer(False);self.assertEqual(cli.resolve(),previous)
    def test_incomplete_extra_and_linked_payloads_are_rejected(self):
        for case in ['missing','extra','link']:
            with self.subTest(case=case):
                original=self.files.copy()
                if case=='missing':self.files.pop('runtime/openvpn')
                if case=='extra':self.files['../escaped']=b'bad'
                self.archive(link=case=='link');self.files=original
                self.manifest['linux_x86_64']['sha256']=hashlib.sha256(self.download.read_bytes()).hexdigest()
                self.run_installer(False);self.assertFalse((self.home/'.local/bin/unblock-2').exists())
    def test_foreign_url_and_old_manifest_fail(self):
        self.manifest['linux_x86_64']['url']='https://example.com/package';self.run_installer(False)
        self.manifest['schema']=1;self.run_installer(False)
    def test_failed_helper_keeps_cli_for_repair_without_claiming_success(self):
        self.env['FIXTURE_EXIT']='1';run=self.run_installer(False)
        self.assertNotIn('Instalação concluída',run.stdout);self.assertTrue((self.home/'.local/bin/unblock-2').is_file())

if __name__=='__main__':unittest.main()
