#!/usr/bin/env bash
# Transport/validation only. No model training code or private logs are published.
set -euo pipefail
exec python3 - "$@" <<'PY'
import concurrent.futures
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

PUBLIC_REPO = 'grewetewe-commits/katalog-data'
FIXED = {'model/info.json', 'meta/badan.json', 'meta/sepatu.json',
         'bank/ready_outfits.json', 'kartu/info.json', 'kartu/tema_graf.json', 'resep/info.json',
         'kartu/badan_bukti.json', 'kartu/badan_bentuk.json', 'fisik3d/perlu_ukur.json', 'kartu/siluet.json'}
SHARDS = re.compile(r'(?:model/item_|meta/harga_|bank/outfit_|kartu/kartu_)(?:0|[1-9][0-9]*)\.json\Z')
# rev 51: keluarga item (keluarga.py) = kelompok opsional sendiri: 8 shard sekaligus atau tidak sama sekali
KELUARGA = re.compile(r'kartu/keluarga_[0-7]\.json\Z')
# rev 58: resep outfit per item. Kelompok OPSIONAL seperti keluarga -- bila belum ada, penerbitan tetap jalan.
RESEP = re.compile(r'resep/resep_(?:0|[1-9][0-9]*)\.json\Z')

class Invalid(Exception):
    pass

def require(ok):
    if not ok:
        raise Invalid('invalid package')

def integer(value, low=1, high=2**53-1):
    require(type(value) is int and low <= value <= high)
    return value

def allowed(name):
    return (name in FIXED or SHARDS.fullmatch(name) is not None
            or KELUARGA.fullmatch(name) is not None or RESEP.fullmatch(name) is not None)

def pairs(entries):
    result = {}
    for key, value in entries:
        require(key not in result)
        result[key] = value
    return result

def decode(raw):
    obj = json.loads(raw, object_pairs_hook=pairs,
                     parse_constant=lambda _: (_ for _ in ()).throw(Invalid('nonfinite')))
    require(isinstance(obj, dict))
    return obj

def validate(files):
    require(files and all(allowed(p) for p in files))
    data = {p: decode(raw) for p, raw in files.items()}
    model, card = data['model/info.json'], data['kartu/info.json']
    mv, cv = integer(model['versi']), integer(card['versi'])
    expected = set()
    for folder, stem, field in [('model', 'item', 'shard_item'),
                                ('meta', 'harga', 'shard_meta'),
                                ('bank', 'outfit', 'shard_bank')]:
        count = integer(model[field], high=256)
        for k in range(count):
            name = f'{folder}/{stem}_{k}.json'
            expected.add(name)
            row = data[name]
            require(type(row['versi']) is int and row['versi'] == mv)
            require(isinstance(row['seeds' if stem == 'outfit' else 'd'], list if stem == 'outfit' else dict))
    count = integer(card['shard'], high=256)
    require(card['skema'] == 7)
    n = 0
    for k in range(count):
        name = f'kartu/kartu_{k}.json'
        expected.add(name)
        row = data[name]
        require(type(row['versi']) is int and row['versi'] == cv and row['skema'] == card['skema'])
        require(isinstance(row['d'], dict))
        for asset, values in row['d'].items():
            require(re.fullmatch(r'[1-9][0-9]*', asset) is not None)
            require(0 < int(asset) < 2**53 and int(asset) % count == k)
            require(isinstance(values, list) and len(values) >= 37)
        n += len(row['d'])
    require(n == integer(card['n']))
    require({p for p in files if SHARDS.fullmatch(p)} == expected)
    for name in ['meta/badan.json', 'meta/sepatu.json']:
        require(type(data[name]['versi']) is int and data[name]['versi'] == mv)
    for name in ['kartu/tema_graf.json', 'kartu/badan_bukti.json']:
        require(type(data[name]['versi']) is int and data[name]['versi'] == cv)
    for name in ['kartu/badan_bentuk.json']:
        if name in data:
            badan = data[name]
            integer(badan['versi'])
            # rev 53b BADAN v2: baris 5-8 kolom bilangan bulat; kelas badan opsional (<= 64 kelas, daftar item genap & bulat)
            require(isinstance(badan['d'], dict))
            for part, row in badan['d'].items():
                require(re.fullmatch(r'[1-9][0-9]*', part) is not None and isinstance(row, list) and 5 <= len(row) <= 8)
                require(all(type(v) is int and -1 <= v < 2**53 for v in row))
            kelas = badan.get('kelas', {})
            require(isinstance(kelas, dict) and len(kelas) <= 64)
            for key, value in kelas.items():
                require(re.fullmatch(r'[0-9]{1,2}', key) is not None and isinstance(value, dict))
                require(isinstance(value.get('i', []), list) and len(value.get('i', [])) % 2 == 0 and len(value.get('i', [])) <= 400)
                require(all(type(v) is int and 0 < v < 2**53 for v in value.get('i', [])))
                require(isinstance(value.get('p', []), list) and all(type(v) is int and -1 <= v <= 1000 for v in value.get('p', [])))
    # rev 58 RESEP: tabel outfit unik + tabel badan + rujukan indeks per item. Semua shard atau tidak sama sekali.
    rsp = sorted(p for p in data if RESEP.fullmatch(p))
    if rsp or 'resep/info.json' in data:
        require('resep/info.json' in data and rsp)
        rinfo = data['resep/info.json']
        rv = integer(rinfo['versi'])
        n_shard = integer(rinfo['shard_resep'], high=256)
        require(rsp == sorted(f'resep/resep_{k}.json' for k in range(n_shard)))
        for k in range(n_shard):
            row = data[f'resep/resep_{k}.json']
            require(row['versi'] == rv)
            outfit, badan, item = row['outfit'], row['badan'], row['item']
            require(isinstance(outfit, list) and isinstance(badan, list) and isinstance(item, dict))
            require(len(outfit) <= 400000 and len(badan) <= 400000)
            for e in outfit:
                require(isinstance(e, dict) and isinstance(e['i'], list) and 1 <= len(e['i']) <= 32)
                require(all(type(v) is int and 0 < v < 2**53 for v in e['i']))
                require(type(e['b']) is int and 0 <= e['b'] < len(badan))
                sep = e.get('s')
                if sep is not None:
                    require(isinstance(sep, list) and len(sep) == 2)
                    require(all(type(v) is int and 0 < v < 2**53 for v in sep))
            for bd in badan:
                require(isinstance(bd, dict) and bd['r'] in ('R6', 'R15'))
                require(isinstance(bd['bp'], list) and len(bd['bp']) == 6)
                require(all(type(v) is int and 0 <= v < 2**53 for v in bd['bp']))
                require(isinstance(bd['sc'], list) and len(bd['sc']) in (0, 6))
                require(all(type(v) in (int, float) and 0 <= v <= 2 for v in bd['sc']))
            for asset, rujuk in item.items():
                require(re.fullmatch(r'[1-9][0-9]*', asset) is not None)
                require(0 < int(asset) < 2**53 and int(asset) % n_shard == k)
                require(isinstance(rujuk, list) and 1 <= len(rujuk) <= 400)
                require(all(type(v) is int and 0 <= v < len(outfit) for v in rujuk))

    kel = sorted(p for p in data if KELUARGA.fullmatch(p))
    if kel:
        require(len(kel) == 8)
        kv = integer(data[kel[0]]['versi'])
        for k in range(8):
            row = data[f'kartu/keluarga_{k}.json']
            require(row['versi'] == kv and isinstance(row['d'], dict))
            for asset, values in row['d'].items():
                require(re.fullmatch(r'[1-9][0-9]*', asset) is not None and int(asset) % 8 == k)
                require(isinstance(values, list) and len(values) % 2 == 0 and len(values) <= 32)
                require(all(type(v) is int and 0 < v < 2**53 for v in values))
    if 'kartu/siluet.json' in data:
        sil = data['kartu/siluet.json']
        integer(sil['versi'])
        require(isinstance(sil['pmi'], dict) and len(sil['pmi']) <= 200)
        for key, value in sil['pmi'].items():
            require(re.fullmatch(r'[0-9],[0-9]\|[0-9],[0-9]', key) is not None)
            require(type(value) in (int, float) and -1.0 <= value <= 1.0)
    if 'fisik3d/perlu_ukur.json' in data:
        requested = data['fisik3d/perlu_ukur.json']
        integer(requested['w'])
        require(isinstance(requested['ids'], list))
        for asset in requested['ids']:
            integer(asset)
    if 'bank/ready_outfits.json' in data:
        ready = data['bank/ready_outfits.json']
        require(ready['schema'] == 1 and isinstance(ready['seeds'], list))
        integer(ready['version'])
    return mv, cv

def git(repo, *args, data=None, env=None):
    # Never forward git diagnostics: private paths, contents or credentials may appear.
    result = subprocess.run(['git', '-C', str(repo), *args], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    if result.returncode:
        raise Invalid('git operation failed')
    return result.stdout

def collect(repo, ref):
    files = {}
    for entry in git(repo, 'ls-tree', '-rz', '--full-tree', ref).split(b'\0'):
        if not entry:
            continue
        meta, rawname = entry.split(b'\t', 1)
        name = rawname.decode('utf-8')
        if not allowed(name):
            continue
        mode, kind, oid = meta.split()
        require(mode in (b'100644', b'100755') and kind == b'blob')
        files[name] = git(repo, 'cat-file', 'blob', oid.decode())
    validate(files)
    return files

def commit_package(repo, files, temp):
    env = dict(os.environ, GIT_INDEX_FILE=str(Path(temp) / 'public.index'),
               GIT_AUTHOR_NAME='github-actions[bot]', GIT_COMMITTER_NAME='github-actions[bot]',
               GIT_AUTHOR_EMAIL='41898282+github-actions[bot]@users.noreply.github.com',
               GIT_COMMITTER_EMAIL='41898282+github-actions[bot]@users.noreply.github.com')
    git(repo, 'read-tree', '--empty', env=env)
    entries = []
    for name, raw in sorted(files.items()):
        oid = git(repo, 'hash-object', '-w', '--stdin', data=raw).strip()
        entries.append(b'100644 ' + oid + b'\t' + name.encode() + b'\0')
    git(repo, 'update-index', '-z', '--index-info', data=b''.join(entries), env=env)
    tree = git(repo, 'write-tree', env=env).strip().decode()
    # No -p: every published snapshot has exactly one root commit.
    return git(repo, 'commit-tree', tree, data=b'Publish validated Roblox data\n', env=env).strip().decode()

def current_public(repo):
    refs = git(repo, 'ls-remote', '--heads', 'origin', 'refs/heads/data').split()
    if not refs:
        return '', None
    git(repo, 'fetch', '-q', '--depth=1', 'origin', '+refs/heads/data:refs/remotes/origin/data')
    sha = git(repo, 'rev-parse', 'refs/remotes/origin/data').strip().decode()
    # Corrupt public data must be investigated; don't silently replace it.
    return sha, collect(repo, sha)

def purge(name):
    try:
        with urllib.request.urlopen(f'https://purge.jsdelivr.net/gh/{PUBLIC_REPO}@data/{name}', timeout=10) as response:
            return response.status == 200
    except Exception:
        return False

MODEL_GROUP = re.compile(r'(?:model/|meta/harga_|bank/outfit_)|meta/badan\.json\Z|meta/sepatu\.json\Z')
KARTU_GROUP = re.compile(r'kartu/(?:info|kartu_[0-9]+|tema_graf|badan_bukti)\.json\Z')

def jumlah_bank(files):
    total = 0
    for name, raw in files.items():
        if name.startswith('bank/outfit_'):
            total += len(decode(raw)['seeds'])
    return total

def ganti_kelompok(files, previous, pola):
    baru = {n: r for n, r in files.items() if not pola.match(n)}
    baru.update({n: r for n, r in previous.items() if pola.match(n)})
    return baru

def jaga_mutu(files, previous):
    """Hasil putaran yang jauh lebih miskin dari versi publik (cache kosong, panen terputus, API Roblox gangguan)
    TIDAK menggantikan versi publik: kelompok model / kartu lama dipertahankan, bagian lain (ready, fisik3d) tetap
    diperbarui. Ambang: item < 85%, bank < 60%, kartu < 85% dari versi publik saat ini."""
    catatan = []
    nm, om = decode(files['model/info.json']), decode(previous['model/info.json'])
    nb, ob = jumlah_bank(files), jumlah_bank(previous)
    if (nm.get('n_item') or 0) < 0.85 * (om.get('n_item') or 0) or nb < 0.6 * ob:
        files = ganti_kelompok(files, previous, MODEL_GROUP)
        catatan.append('Model baru lebih miskin dari versi publik; versi publik dipertahankan.')
    nk, ok_ = decode(files['kartu/info.json']), decode(previous['kartu/info.json'])
    if (nk.get('n') or 0) < 0.85 * (ok_.get('n') or 0):
        files = ganti_kelompok(files, previous, KARTU_GROUP)
        catatan.append('Kartu baru lebih miskin dari versi publik; versi publik dipertahankan.')
    return files, catatan

def publish(private, public):
    for attempt in range(3):
        try:
            git(private, 'fetch', '-q', '--depth=1', 'origin', '+refs/heads/data:refs/remotes/origin/data')
            files = collect(private, 'refs/remotes/origin/data')
            mv, cv = validate(files)
            old, previous = current_public(public)
            if previous:
                files, catatan = jaga_mutu(files, previous)
                for c in catatan:
                    print(c)
                mv, cv = validate(files)
                pm, pc = validate(previous)
                require(mv >= pm and cv >= pc)
                # Independently generated optional data must not vanish or move backwards.
                if 'kartu/siluet.json' in previous and 'kartu/siluet.json' not in files:
                    files['kartu/siluet.json'] = previous['kartu/siluet.json']
                for name in ['bank/ready_outfits.json', 'kartu/badan_bentuk.json', 'fisik3d/perlu_ukur.json']:
                    if name in previous:
                        require(name in files)
                        field = 'version' if name.startswith('bank/') else ('w' if name.startswith('fisik3d/') else 'versi')
                        require(decode(files[name])[field] >= decode(previous[name])[field])
                # keluarga: bila putaran ini tidak membawanya, versi publik lama tetap dipakai
                if not any(KELUARGA.fullmatch(n) for n in files):
                    files.update({n: r for n, r in previous.items() if KELUARGA.fullmatch(n)})
            with tempfile.TemporaryDirectory(prefix='katalog-publish-') as temp:
                commit = commit_package(public, files, temp)
                git(public, 'push', '-q', f'--force-with-lease=refs/heads/data:{old}',
                    'origin', f'{commit}:refs/heads/data')
            print(f'Paket valid diterbitkan: {len(files)} file; model {mv}; kartu {cv}.')
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                results = list(pool.map(purge, sorted(files)))
            print(f'Penyegaran CDN: {sum(results)}/{len(results)}; kegagalan CDN tidak membatalkan data.')
            return
        except Invalid:
            if attempt == 2:
                raise
            time.sleep(2 * (attempt + 1))

def main():
    if len(sys.argv) == 4 and sys.argv[1] == '--validate':
        files = collect(Path(sys.argv[2]).resolve(), sys.argv[3])
        mv, cv = validate(files)
        print(f'Valid: {len(files)} file; model {mv}; kartu {cv}.')
        for name in sorted(files):
            print(name)
        return
    require(len(sys.argv) == 3 and os.environ.get('GITHUB_REPOSITORY') == PUBLIC_REPO)
    private, public = map(lambda p: Path(p).resolve(), sys.argv[1:])
    require(private != public)
    publish(private, public)

if __name__ == '__main__':
    try:
        main()
    except Exception:
        # Do not print exception messages/tracebacks from private JSON or git.
        print('::error::Penerbitan gagal. Periksa izin atau integritas paket di repo dapur; data publik dipertahankan.')
        sys.exit(1)
PY
