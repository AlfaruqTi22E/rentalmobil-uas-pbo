-- =====================================================================
-- DATABASE: rental_mobil
-- Project  : Aplikasi Rental Mobil Berbasis Java GUI dan MySQL
-- Berisi   : Tabel, Stored Procedure, Function, Trigger, View
-- =====================================================================

DROP DATABASE IF EXISTS rental_mobil;
CREATE DATABASE rental_mobil;
USE rental_mobil;

-- ---------------------------------------------------------------------
-- TABEL: users  (akun untuk login aplikasi)
-- ---------------------------------------------------------------------
CREATE TABLE users (
    id_user     INT AUTO_INCREMENT PRIMARY KEY,
    username    VARCHAR(50) NOT NULL UNIQUE,
    password    VARCHAR(100) NOT NULL,
    nama        VARCHAR(100) NOT NULL,
    role        ENUM('Admin','Kasir') NOT NULL DEFAULT 'Kasir',
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- TABEL: mobil
-- ---------------------------------------------------------------------
CREATE TABLE mobil (
    id_mobil    INT AUTO_INCREMENT PRIMARY KEY,
    merk        VARCHAR(50) NOT NULL,
    model       VARCHAR(50) NOT NULL,
    tahun       INT NOT NULL,
    plat_nomor  VARCHAR(20) NOT NULL UNIQUE,
    harga_sewa  DECIMAL(12,2) NOT NULL,
    status      ENUM('Tersedia','Disewa') NOT NULL DEFAULT 'Tersedia'
);

-- ---------------------------------------------------------------------
-- TABEL: pelanggan
-- ---------------------------------------------------------------------
CREATE TABLE pelanggan (
    id_pelanggan INT AUTO_INCREMENT PRIMARY KEY,
    nama         VARCHAR(100) NOT NULL,
    alamat       VARCHAR(200),
    no_telp      VARCHAR(20),
    no_ktp       VARCHAR(30) NOT NULL UNIQUE
);

-- ---------------------------------------------------------------------
-- TABEL: transaksi
-- ---------------------------------------------------------------------
CREATE TABLE transaksi (
    id_transaksi        INT AUTO_INCREMENT PRIMARY KEY,
    id_mobil             INT NOT NULL,
    id_pelanggan         INT NOT NULL,
    id_user              INT NOT NULL,
    tanggal_sewa          DATE NOT NULL,
    tanggal_kembali_rencana DATE NOT NULL,
    tanggal_kembali_aktual  DATE NULL,
    total_biaya           DECIMAL(12,2) NOT NULL,
    status                ENUM('Berjalan','Selesai') NOT NULL DEFAULT 'Berjalan',
    CONSTRAINT fk_transaksi_mobil FOREIGN KEY (id_mobil) REFERENCES mobil(id_mobil),
    CONSTRAINT fk_transaksi_pelanggan FOREIGN KEY (id_pelanggan) REFERENCES pelanggan(id_pelanggan),
    CONSTRAINT fk_transaksi_user FOREIGN KEY (id_user) REFERENCES users(id_user)
);

-- ---------------------------------------------------------------------
-- DATA AWAL
-- ---------------------------------------------------------------------
INSERT INTO users (username, password, nama, role) VALUES
('admin', 'admin123', 'Administrator', 'Admin'),
('kasir1', 'kasir123', 'Budi Kasir', 'Kasir');

INSERT INTO mobil (merk, model, tahun, plat_nomor, harga_sewa, status) VALUES
('Toyota', 'Avanza', 2022, 'D 1234 AB', 300000, 'Tersedia'),
('Honda', 'Brio', 2021, 'D 5678 CD', 250000, 'Tersedia'),
('Daihatsu', 'Xenia', 2023, 'D 9012 EF', 320000, 'Tersedia');

INSERT INTO pelanggan (nama, alamat, no_telp, no_ktp) VALUES
('Andi Pratama', 'Jl. Merdeka No.1, Bandung', '081234567890', '3273010101900001'),
('Sri Wulandari', 'Jl. Sudirman No.5, Bandung', '081298765432', '3273010101900002');

-- ---------------------------------------------------------------------
-- FUNCTION: fn_hitung_biaya
-- Menghitung total biaya sewa = jumlah hari x harga sewa per hari
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE FUNCTION fn_hitung_biaya(
    p_tanggal_sewa DATE,
    p_tanggal_kembali DATE,
    p_harga_sewa DECIMAL(12,2)
)
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    DECLARE v_jumlah_hari INT;
    DECLARE v_total DECIMAL(12,2);

    SET v_jumlah_hari = DATEDIFF(p_tanggal_kembali, p_tanggal_sewa);
    IF v_jumlah_hari <= 0 THEN
        SET v_jumlah_hari = 1;
    END IF;

    SET v_total = v_jumlah_hari * p_harga_sewa;
    RETURN v_total;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- STORED PROCEDURE: sp_tambah_transaksi
-- Menambah transaksi penyewaan baru, memakai fn_hitung_biaya
-- untuk menghitung total biaya secara otomatis.
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE PROCEDURE sp_tambah_transaksi(
    IN p_id_mobil INT,
    IN p_id_pelanggan INT,
    IN p_id_user INT,
    IN p_tanggal_sewa DATE,
    IN p_tanggal_kembali_rencana DATE
)
BEGIN
    DECLARE v_harga_sewa DECIMAL(12,2);
    DECLARE v_status_mobil VARCHAR(20);
    DECLARE v_total_biaya DECIMAL(12,2);

    SELECT harga_sewa, status INTO v_harga_sewa, v_status_mobil
    FROM mobil WHERE id_mobil = p_id_mobil;

    IF v_status_mobil <> 'Tersedia' THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Mobil sedang disewa, tidak dapat diproses.';
    ELSE
        SET v_total_biaya = fn_hitung_biaya(p_tanggal_sewa, p_tanggal_kembali_rencana, v_harga_sewa);

        INSERT INTO transaksi (id_mobil, id_pelanggan, id_user, tanggal_sewa,
                                tanggal_kembali_rencana, total_biaya, status)
        VALUES (p_id_mobil, p_id_pelanggan, p_id_user, p_tanggal_sewa,
                p_tanggal_kembali_rencana, v_total_biaya, 'Berjalan');
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- TRIGGER: trg_after_insert_transaksi
-- Setelah transaksi baru dibuat, status mobil otomatis jadi 'Disewa'
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_after_insert_transaksi
AFTER INSERT ON transaksi
FOR EACH ROW
BEGIN
    UPDATE mobil SET status = 'Disewa' WHERE id_mobil = NEW.id_mobil;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- TRIGGER: trg_after_update_transaksi
-- Ketika transaksi diubah menjadi 'Selesai', status mobil kembali 'Tersedia'
-- ---------------------------------------------------------------------
DELIMITER $$
CREATE TRIGGER trg_after_update_transaksi
AFTER UPDATE ON transaksi
FOR EACH ROW
BEGIN
    IF NEW.status = 'Selesai' AND OLD.status <> 'Selesai' THEN
        UPDATE mobil SET status = 'Tersedia' WHERE id_mobil = NEW.id_mobil;
    END IF;
END$$
DELIMITER ;

-- ---------------------------------------------------------------------
-- VIEW: view_laporan_penyewaan
-- Menggabungkan transaksi, mobil, pelanggan, dan user untuk laporan
-- ---------------------------------------------------------------------
CREATE VIEW view_laporan_penyewaan AS
SELECT
    t.id_transaksi,
    p.nama          AS nama_pelanggan,
    m.merk,
    m.model,
    m.plat_nomor,
    u.nama          AS petugas,
    t.tanggal_sewa,
    t.tanggal_kembali_rencana,
    t.tanggal_kembali_aktual,
    t.total_biaya,
    t.status
FROM transaksi t
JOIN mobil m       ON t.id_mobil = m.id_mobil
JOIN pelanggan p   ON t.id_pelanggan = p.id_pelanggan
JOIN users u       ON t.id_user = u.id_user
ORDER BY t.id_transaksi DESC;

-- ---------------------------------------------------------------------
-- CONTOH PENGGUNAAN (uji coba manual)
-- ---------------------------------------------------------------------
-- CALL sp_tambah_transaksi(1, 1, 1, '2026-07-16', '2026-07-20');
-- SELECT * FROM view_laporan_penyewaan;
