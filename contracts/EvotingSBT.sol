// SPDX-License-Identifier: GPL-3.0
pragma solidity >= 0.8.2 < 0.9.0;

/**
 * @title EvotingSBT
 * @notice Gasless Soulbound Token (ERC-5192) E-Voting Smart Contract
 * @dev Menggabungkan tiket hak suara non-transferable on-chain dengan meta-transaksi EIP-712 (0 ETH Gasless Vote)
 */
contract EvotingSBT {

    // --- METADATA SOULBOUND TOKEN (ERC-721 / ERC-5192 NON-TRANSFERABLE) ---
    string public constant name = "VoteDecen Official Voter Ballot";
    string public constant symbol = "VOTE-SBT";

    address public owner;
    bool public sudahBisaVoting;
    bool public votingSelesai;

    struct Kandidat {
        address alamatKandidat;
        uint jumlahSuara;
    }

    struct BallotTicket {
        uint256 tokenId;
        uint256 sessionId;
        bool isUsed;
    }

    Kandidat[] public kandidat;
    mapping(address => bool) public kandidatTerdaftar;

    // Mapping SBT: Owner => SessionId => BallotTicket
    mapping(address => mapping(uint256 => BallotTicket)) public voterBallots;
    mapping(address => bool) public userSudahVotingMap;
    
    // Standar kepemilikan NFT
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;

    uint256 private _nextTokenId = 1;

    // --- FITUR GASLESS META-TRANSACTION (EIP-712) ---
    mapping(address => uint256) public nonces;
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 public constant BALLOT_VOTE_TYPEHASH = keccak256(
        "VoteWithBallot(uint256 candidateIndex,uint256 sessionId,address voter,uint256 nonce,uint256 deadline)"
    );

    // Events ERC-5192 & Sistem Voting
    event BallotMinted(address indexed voter, uint256 indexed tokenId, uint256 indexed sessionId);
    event BallotConsumed(address indexed voter, uint256 indexed tokenId, uint256 candidateIndex);
    event Locked(uint256 tokenId); // Sesuai standar ERC-5192 (Soulbound)

    constructor() {
        owner = msg.sender;
        sudahBisaVoting = false;
        votingSelesai = false;

        uint256 chainId = block.chainid;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VoteDecenSBT")),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Anda Bukan Owner");
        _;
    }

    // =========================================================================
    // 1. MANAJEMEN SOULBOUND TOKEN (MINTING OLEH PANITIA)
    // =========================================================================

    /**
     * @notice Panitia menerbitkan 1 NFT Tiket Suara ke wallet pemilih yang terverifikasi.
     */
    function mintBallot(address _voter, uint256 _sessionId) public onlyOwner returns (uint256) {
        require(_voter != address(0), "Alamat pemilih tidak valid");
        require(_voter != owner, "Owner tidak boleh menerima tiket suara");
        require(voterBallots[_voter][_sessionId].tokenId == 0, "Pemilih sudah memiliki tiket untuk sesi ini!");

        uint256 tokenId = _nextTokenId++;
        _owners[tokenId] = _voter;
        _balances[_voter]++;

        voterBallots[_voter][_sessionId] = BallotTicket({
            tokenId: tokenId,
            sessionId: _sessionId,
            isUsed: false
        });

        emit BallotMinted(_voter, tokenId, _sessionId);
        emit Locked(tokenId); // ERC-5192: Menandai token terkunci permanen pada wallet

        return tokenId;
    }

    // ERC-721 Read Helpers
    function ownerOf(uint256 tokenId) public view returns (address) {
        address tokenOwner = _owners[tokenId];
        require(tokenOwner != address(0), "Token ID tidak valid");
        return tokenOwner;
    }

    function balanceOf(address account) public view returns (uint256) {
        require(account != address(0), "Alamat nol tidak valid");
        return _balances[account];
    }

    /**
     * @dev ERC-5192: Token selalu terkunci (Soulbound)
     */
    function locked(uint256 tokenId) external view returns (bool) {
        require(_owners[tokenId] != address(0), "Token tidak valid");
        return true;
    }

    /**
     * @dev ERC-5192 & ERC-721: Memblokir transfer. Token bersifat Soulbound permanen.
     */
    function transferFrom(address, address, uint256) public pure {
        revert("SOULBOUND_TOKEN: Tiket hak suara tidak dapat dipindahtangankan!");
    }

    function safeTransferFrom(address, address, uint256) public pure {
        revert("SOULBOUND_TOKEN: Tiket hak suara tidak dapat dipindahtangankan!");
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure {
        revert("SOULBOUND_TOKEN: Tiket hak suara tidak dapat dipindahtangankan!");
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(_owners[tokenId] != address(0), "Token tidak valid");
        return string(
            abi.encodePacked(
                'data:application/json;utf8,{"name":"VoteDecen Official Voter Ballot #',
                _toString(tokenId),
                '","description":"Official Soulbound Voter Ballot (ERC-5192) - 0 ETH Gasless E-Voting","attributes":[{"trait_type":"Soulbound","value":"true"}]}'
            )
        );
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5bced73b // ERC721Metadata
            || interfaceId == 0xb45a3c0e; // ERC5192
    }

    // =========================================================================
    // 2. MANAJEMEN KANDIDAT & STATUS VOTING
    // =========================================================================

    function tambahKandidat(address _adrs) public onlyOwner {
        require(_adrs != address(0), "Alamat tidak valid");
        require(!kandidatTerdaftar[_adrs], "Kandidat Sudah Terdaftar");
        kandidat.push(Kandidat(_adrs, 0));
        kandidatTerdaftar[_adrs] = true;
    }

    function hapusKandidat(address _adrs) public onlyOwner {
        require(kandidatTerdaftar[_adrs], "Kandidat tidak terdaftar");
        kandidatTerdaftar[_adrs] = false;
        
        for (uint i = 0; i < kandidat.length; i++) {
            if (kandidat[i].alamatKandidat == _adrs) {
                kandidat[i] = kandidat[kandidat.length - 1];
                kandidat.pop();
                break;
            }
        }
    }

    function statusVoting(bool _status) public onlyOwner {
        sudahBisaVoting = _status;
    }

    function votingSudahSelesai() public onlyOwner {
        votingSelesai = true;
        sudahBisaVoting = false;
    }

    function totalKandidat() public view returns (uint) {
        return kandidat.length;
    }

    // =========================================================================
    // 3. VOTING: GASLESS DENGAN TIKET SBT (0 ETH UNTUK PEMILIH)
    // =========================================================================

    /**
     * @notice Eksekusi voting Gasless menggunakan tanda tangan digital pemilih pemegang SBT (EIP-712).
     * @dev Dipanggil oleh Relayer Panitia yang menanggung gas fee transaksi.
     */
    function voteWithBallotBySig(
        uint256 _candidateIndex,
        uint256 _sessionId,
        address _voter,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public {
        require(block.timestamp <= _deadline, "Tanda tangan voting sudah kadaluarsa!");
        require(_voter != address(0), "Alamat pemilih tidak valid");

        // 1. Verifikasi Signature Kriptografi EIP-712
        bytes32 structHash = keccak256(
            abi.encode(
                BALLOT_VOTE_TYPEHASH,
                _candidateIndex,
                _sessionId,
                _voter,
                nonces[_voter],
                _deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                structHash
            )
        );

        address signer = ecrecover(digest, _v, _r, _s);
        require(signer != address(0) && signer == _voter, "Tanda tangan digital tidak valid!");

        // Naikkan nonce pemilih (Anti-Replay Attack)
        nonces[_voter]++;

        // 2. Eksekusi Pencoblosan & Konsumsi SBT
        _consumeBallotAndVote(_voter, _candidateIndex, _sessionId);
    }

    /**
     * @notice Opsi voting langsung on-chain (jika pemilih ingin bayar gas sendiri).
     */
    function voteWithBallot(uint256 _candidateIndex, uint256 _sessionId) public {
        _consumeBallotAndVote(msg.sender, _candidateIndex, _sessionId);
    }

    /**
     * @notice Kompatibilitas mundur dengan fungsi voting lama.
     */
    function voting(uint256 _candidateIndex) public {
        _consumeBallotAndVote(msg.sender, _candidateIndex, 1);
    }

    function _consumeBallotAndVote(address _voter, uint256 _candidateIndex, uint256 _sessionId) internal {
        require(sudahBisaVoting, "Voting Belum Dimulai");
        require(!votingSelesai, "Voting Sudah Berakhir");
        require(_candidateIndex < kandidat.length, "Kandidat Tidak Tersedia");

        BallotTicket storage ticket = voterBallots[_voter][_sessionId];

        // Validasi Kepemilikan & Status Tiket SBT
        require(ticket.tokenId != 0, "Anda tidak memiliki NFT Tiket Suara resmi untuk sesi ini!");
        require(!ticket.isUsed, "NFT Tiket Suara Anda sudah pernah digunakan untuk mencoblos!");

        // Hanguskan tiket & catat suara
        ticket.isUsed = true;
        userSudahVotingMap[_voter] = true;
        kandidat[_candidateIndex].jumlahSuara++;

        emit BallotConsumed(_voter, ticket.tokenId, _candidateIndex);
    }

    // Helper cek status tiket pemilih
    function checkVoterTicket(address _voter, uint256 _sessionId) external view returns (
        bool hasTicket,
        uint256 tokenId,
        bool isUsed
    ) {
        BallotTicket memory ticket = voterBallots[_voter][_sessionId];
        return (ticket.tokenId != 0, ticket.tokenId, ticket.isUsed);
    }

    // Kompatibilitas mundur fungsi userSudahVoting
    function userSudahVoting(address _voter) external view returns (bool) {
        return userSudahVotingMap[_voter];
    }

    function hasilVoting() public view returns (address alamatPemenang, uint totalSuara) {
        require(!sudahBisaVoting, "Proses voting masih berjalan!");
        require(kandidat.length > 0, "Belum ada kandidat terdaftar");
        require(votingSelesai, "Voting belum selesai");

        uint maxVotes = 0;
        uint indexPemenang = 0;
        bool adaPemenang = false;

        for (uint i = 0; i < kandidat.length; i++) {
            if (kandidat[i].jumlahSuara > maxVotes) {
                maxVotes = kandidat[i].jumlahSuara;
                indexPemenang = i;
                adaPemenang = true;
            }
        }

        require(adaPemenang || kandidat[0].jumlahSuara > 0, "Belum ada suara masuk");
        return (kandidat[indexPemenang].alamatKandidat, kandidat[indexPemenang].jumlahSuara);
    }
}
