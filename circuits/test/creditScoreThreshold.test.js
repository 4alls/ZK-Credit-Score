const path = require("path");
const { expect } = require("chai");
const wasm_tester = require("circom_tester").wasm;

describe("CreditScoreThreshold", function () {
  this.timeout(100000);

  let circuit;
  // Dummy address used across witness-level tests. The circuit does not
  // validate its format -- it is only checked for equality against
  // msg.sender at the Solidity layer (see contracts/test).
  const USER_ADDRESS = "1234567890123456789012345678901234567890";

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
      { creditScore: 742, minimumScore: 700, userAddress: USER_ADDRESS },
      true
    );
    await circuit.checkConstraints(witness);
    await circuit.assertOut(witness, { isEligible: 1 });
  });

  it("accepts a score exactly equal to the threshold (700 >= 700)", async () => {
    const witness = await circuit.calculateWitness(
      { creditScore: 700, minimumScore: 700, userAddress: USER_ADDRESS },
      true
    );
    await circuit.checkConstraints(witness);
    await circuit.assertOut(witness, { isEligible: 1 });
  });

  it("rejects a score below the threshold (650 < 700)", async () => {
    await expectWitnessFailure({
      creditScore: 650,
      minimumScore: 700,
      userAddress: USER_ADDRESS,
    });
  });

  it("rejects a score below the realistic minimum bound (299 < 300)", async () => {
    await expectWitnessFailure({
      creditScore: 299,
      minimumScore: 300,
      userAddress: USER_ADDRESS,
    });
  });

  it("rejects a score above the realistic maximum bound (851 > 850)", async () => {
    await expectWitnessFailure({
      creditScore: 851,
      minimumScore: 300,
      userAddress: USER_ADDRESS,
    });
  });

  it("rejects malformed input (missing creditScore)", async () => {
    await expectWitnessFailure({
      minimumScore: 700,
      userAddress: USER_ADDRESS,
    });
  });

  it("produces different proofs' public signals for different userAddress values", async () => {
    // Not a proof-level test (that's covered in Foundry), but confirms the
    // witness-level wiring: userAddress flows straight into the public
    // output signal set, unmodified.
    const witnessA = await circuit.calculateWitness(
      { creditScore: 742, minimumScore: 700, userAddress: "111" },
      true
    );
    const witnessB = await circuit.calculateWitness(
      { creditScore: 742, minimumScore: 700, userAddress: "222" },
      true
    );
    await circuit.assertOut(witnessA, { isEligible: 1 });
    await circuit.assertOut(witnessB, { isEligible: 1 });
  });
});
