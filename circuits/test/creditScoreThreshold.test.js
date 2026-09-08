const path = require("path");
const { expect } = require("chai");
const wasm_tester = require("circom_tester").wasm;

describe("CreditScoreThreshold", function () {
  this.timeout(100000);

  let circuit;

  before(async () => {
    circuit = await wasm_tester(
      path.join(__dirname, "..", "src", "creditScoreThreshold.circom"),
      { include: path.join(__dirname, "..", "node_modules") }
    );
  });

  async function expectWitnessFailure(input) {
    let threw = false;
    try {
      await circuit.calculateWitness(input, true);
    } catch (err) {
      threw = true;
    }
    expect(threw, "expected witness generation to fail").to.be.true;
  }

  it("accepts a score strictly above the threshold (742 >= 700)", async () => {
    const witness = await circuit.calculateWitness(
      { creditScore: 742, minimumScore: 700 },
      true
    );
    await circuit.checkConstraints(witness);
    await circuit.assertOut(witness, { isEligible: 1 });
  });

  it("accepts a score exactly equal to the threshold (700 >= 700)", async () => {
    const witness = await circuit.calculateWitness(
      { creditScore: 700, minimumScore: 700 },
      true
    );
    await circuit.checkConstraints(witness);
    await circuit.assertOut(witness, { isEligible: 1 });
  });

  it("rejects a score below the threshold (650 < 700)", async () => {
    await expectWitnessFailure({ creditScore: 650, minimumScore: 700 });
  });

  it("rejects a score below the realistic minimum bound (299 < 300)", async () => {
    await expectWitnessFailure({ creditScore: 299, minimumScore: 300 });
  });

  it("rejects a score above the realistic maximum bound (851 > 850)", async () => {
    await expectWitnessFailure({ creditScore: 851, minimumScore: 300 });
  });

  it("rejects malformed input (missing creditScore)", async () => {
    await expectWitnessFailure({ minimumScore: 700 });
  });
});
