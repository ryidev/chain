// SPDX-License-Identifier: GPL-3.0
pragma solidity >= 0.8.2 < 0.9.0;

contract Evoting {

    address public owner;
    bool public sudahBisaVoting; 
    bool votingSelesai;

    struct Kandidat {
        address alamatKandidat;
        uint jumlahSuara;
    }

    Kandidat[] public kandidat;
    mapping(address => bool) public kandidatTerdaftar;
    mapping(address => bool) public userSudahVoting;

    constructor() {
        owner = msg.sender;
        sudahBisaVoting = false;
        votingSelesai = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Anda Bukan Owner");
        _;
    }

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

    function totalKandidat() public view returns (uint) {
        return kandidat.length;
    }

    function votingSudahSelesai() public {
      require(msg.sender == owner, "anda bukan owner");
      votingSelesai = true;
      sudahBisaVoting = false;
    }

    function voting(uint _index) public {
        require(sudahBisaVoting, "Voting Belum Dimulai");
        require(_index < kandidat.length, "Kandidat Tidak Tersedia");
        require(!userSudahVoting[msg.sender], "Anda Sudah Memilih");
        require(msg.sender != owner, "Owner tidak diperbolehkan voting");

        userSudahVoting[msg.sender] = true;
        kandidat[_index].jumlahSuara++;
    }

    function hasilVoting() public view returns (address alamatPemenang, uint totalSuara) {
        require(!sudahBisaVoting, "Proses voting masih berjalan, matikan dulu!");
        require(kandidat.length > 0, "Belum ada kandidat terdaftar");
        require(votingSelesai, "voting belum dilaksanakan");

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
