/*
 * Copyright 2019, Offchain Labs, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

pragma solidity ^0.5.3;

library MerkleLib {
  function generateAddressRoot(address[] memory _addresses) public pure returns (bytes32) {
    bytes32[] memory _hashes = new bytes32[](_addresses.length);
    for (uint i = 0; i < _addresses.length; i++) {
      _hashes[i] = bytes32(bytes20(_addresses[i]));
    }
    return generateRoot(_hashes);
  }

	function generateRoot(bytes32[] memory _hashes) public pure returns (bytes32) {
    while (_hashes.length > 1) {
      bytes32[] memory nextLayer = new bytes32[]((_hashes.length + 1) / 2);
      for (uint i = 0; i < nextLayer.length; i++) {
          if (2 * i + 1 < _hashes.length) {
          	nextLayer[i] = keccak256(abi.encodePacked(_hashes[2 * i], _hashes[2 * i + 1]));
          } else {
          	nextLayer[i] = _hashes[2 * i];
          }
      }
      _hashes = nextLayer;
    }
    return _hashes[0];
  }

  function verifyProof(
      bytes memory proof,
      bytes32 root,
      bytes32 hash,
      uint256 index
  ) public pure returns (bool) {
    // use the index to determine the node ordering
    // index ranges 1 to n

    bytes32 el;
    bytes32 h = hash;
    uint256 remaining;

    for (uint256 j = 32; j <= proof.length; j += 32) {
      assembly {
        el := mload(add(proof, j))
      }

      // calculate remaining elements in proof
      remaining = (proof.length - j + 32) / 32;

      // we don't assume that the tree is padded to a power of 2
      // if the index is odd then the proof will start with a hash at a higher
      // layer, so we have to adjust the index to be the index at that layer
      while (remaining > 0 && index % 2 == 1 && index > 2 ** remaining) {
        index = uint(index) / 2 + 1;
      }

      if (index % 2 == 0) {
        h = keccak256(abi.encodePacked(el, h));
        index = index / 2;
      } else {
        h = keccak256(abi.encodePacked(h, el));
        index = uint(index) / 2 + 1;
      }
    }

    return h == root;
  }
}
