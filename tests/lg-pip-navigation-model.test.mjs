import assert from 'node:assert/strict';
import test from 'node:test';

function step(rows, selected, direction) {
  for (let remaining = rows.length; remaining > 0; remaining -= 1) {
    selected = (selected + direction + rows.length) % rows.length;
    if (rows[selected].flag !== 2) return selected;
  }
  throw new Error('No selectable item');
}

function firstEnabled(rows) {
  const selected = rows.findIndex(row => row.flag !== 2);
  if (selected < 0) throw new Error('No selectable item');
  return selected;
}

function candidatePlan({ d7Value, pipCapability }) {
  if (d7Value !== 1) throw new Error('A confirmed single-picture state is required');
  if (pipCapability !== 2) throw new Error('The calibrated PIP capability is required');
  return ['reset', 'menu', 'up', 'up', 'ok', 'up', 'ok', 'up', 'ok'];
}

test('two Up steps reach Input when Input and General remain the final enabled rows', () => {
  for (const kinds of [[0, 1, 2, 4, 5], [1, 2, 3, 4, 5]]) {
    for (let disabledMask = 0; disabledMask < 8; disabledMask += 1) {
      const flags = [0, 1, 2].map(index => disabledMask & (1 << index) ? 2 : 0).concat([0, 0]);
      const rows = kinds.map((kind, index) => ({ kind, flag: flags[index] }));
      let selected = firstEnabled(rows);
      selected = step(rows, selected, -1);
      selected = step(rows, selected, -1);
      assert.equal(rows[selected].kind, 4);
    }
  }
});

test('the rejected three-Down sequence has disabled-root counterexamples', () => {
  const enabledRows = [0, 1, 2, 4, 5].map(kind => ({ kind, flag: 0 }));
  let nominalSelection = 0;
  for (let count = 0; count < 3; count += 1) nominalSelection = step(enabledRows, nominalSelection, 1);
  assert.equal(enabledRows[nominalSelection].kind, 4);

  for (const flags of [[2, 0, 0, 0, 0], [2, 2, 0, 0, 0]]) {
    const rows = [0, 1, 2, 4, 5].map((kind, index) => ({ kind, flag: flags[index] }));
    let selected = firstEnabled(rows);
    for (let count = 0; count < 3; count += 1) selected = step(rows, selected, 1);
    assert.notEqual(rows[selected].kind, 4);
  }
});

test('one Up reaches PBP/PIP when all later off-state rows are disabled', () => {
  for (const aspectFlag of [0, 2]) {
    for (const autoInputFlag of [null, 0, 2]) {
      for (const trailingCount of [1, 2, 3, 4]) {
        const rows = [{ kind: 0, flag: 0 }, { kind: 1, flag: aspectFlag }];
        if (autoInputFlag !== null) rows.push({ kind: 2, flag: autoInputFlag });
        rows.push({ kind: 3, flag: 0 });
        for (let index = 0; index < trailingCount; index += 1) {
          rows.push({ kind: 4 + index, flag: 2 });
        }
        assert.equal(rows[step(rows, 0, -1)].kind, 3);
      }
    }
  }
  for (const autoInputFlag of [null, 0, 2]) {
    const rows = [{ kind: 0, flag: 0 }, { kind: 1, flag: 2 }];
    if (autoInputFlag !== null) rows.push({ kind: 2, flag: autoInputFlag });
    rows.push({ kind: 3, flag: 0 }, { kind: 6, flag: 2 }, { kind: 7, flag: 2 });
    const selected = step(rows, step(rows, 0, 1), 1);
    assert.equal(rows[selected].kind, autoInputFlag === 0 ? 3 : 0);
  }
});

test('one Up selects the last PIP option from the confirmed off option', () => {
  for (const pipValue of [6, 7, 8, 9]) {
    for (const middleValues of [[1], [1, 3, 4]]) {
      for (const pbpDisabled of [false, true]) {
        const rows = [0, ...middleValues, pipValue].map(kind => ({
          kind,
          flag: kind === 1 && pbpDisabled ? 2 : 0,
        }));
        assert.equal(rows[step(rows, 0, -1)].kind, pipValue);
      }
    }
  }
});

test('no candidate is produced for unknown or non-single-picture states', () => {
  for (const d7Value of [undefined, null, 0, 3, 5, 255]) {
    assert.throws(() => candidatePlan({ d7Value, pipCapability: 2 }), /single-picture/);
  }
  for (const pipCapability of [undefined, null, 0, 1, 3]) {
    assert.throws(() => candidatePlan({ d7Value: 1, pipCapability }), /PIP capability/);
  }
  assert.deepEqual(candidatePlan({ d7Value: 1, pipCapability: 2 }), [
    'reset', 'menu', 'up', 'up', 'ok', 'up', 'ok', 'up', 'ok',
  ]);
});

test('the off-state precondition is necessary for the last-enabled-row rule', () => {
  const activeLayoutRows = [0, 1, 2, 3, 6, 7].map(kind => ({ kind, flag: 0 }));
  assert.notEqual(activeLayoutRows[step(activeLayoutRows, 0, -1)].kind, 3);
  assert.throws(() => step([{ kind: 0, flag: 2 }], 0, -1), /No selectable item/);
});
