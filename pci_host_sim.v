// ************************************************************************* //
// PCIターゲット7 (パリティ生成&バースト転送ディスコネクト対応)
// ************************************************************************* //
`default_nettype wire

module PCI_HOST_SIM
	(

	// PCIバス信号ピン(使用する信号) //
		input				PCICLK		,						// PCIバスクロック
		input				RST_n		,						// 非同期リセット
		inout		[31:0]	PCIAD		,						// アドレス/データバス
		inout		[ 3:0]	C_BE_n		,						// PCIバスコマンド/バイトイネーブル
		inout				FRAME_n		,						// フレーム
		inout				IRDY_n		,						// イニシエータレディ
		inout				DEVSEL_n	,						// デバイスセレクション
		inout				TRDY_n		,						// ターゲットレディ
		inout				STOP_n		,						// 転送ストップ要求
		inout				PAR			,						// パリティビット
		input				IDSEL		,						// コンフィグレーションデバイスセレクト
		output				INTA_n		, 						// 割り込み出力 INTA#
		output				REQ_n		, 						// バス使用要求信号
		input				GNT_n		,						// バス使用許諾信号

	// PCIバス信号ピン(未使用な信号) //
		output				PERR_n		, 						// パリティエラー
		output				SERR_n		, 						// システムエラー
		output				INTB_n		, 						// 割り込み出力 INTB#
		output				INTC_n		, 						// 割り込み出力 INTC#
		output				INTD_n		,						// 割り込み出力 INTD#

	// ローカルバス信号ピン
		output		[23:0]	MEM_ADRS	,						// メモリアドレスバス
		inout		[31:0]	MEM_DATA	,						// メモリデータバス
		output	reg			MEM_CEn		,						// SRAM0〜3 /CE
		output	reg			MEM_OEn		,						// SRAM0〜3 /OE
		output	reg			MEM_WE0n	,						//- SRAM0 /WE
		output	reg			MEM_WE1n	,						// SRAM1 /WE
		output	reg			MEM_WE2n	,						// SRAM2 /WE
		output	reg			MEM_WE3n	,						// SRAM3 /WE

	// 外部割り込み入力ピン
		input				INT_IN3		,						// 割り込み入力3
		input				INT_IN2		,						// 割り込み入力2
		input				INT_IN1		,						// 割り込み入力1
		input				INT_IN0								// 割り込み入力0

	);

// ************************************************************************* //
// **********	レジスタ/定数 定義部分
// ************************************************************************* //

	parameter	tPD = 10 ;			// シミュレーション用擬似遅延パラメータ

// PCIバスコマンド/アドレス/IDSELホールドレジスタ //
	reg			[3:0]	PCI_BusCommand ;					// PCIバスコマンドレジスタ
	reg			[31:0]	PCI_Address	;						// PCIアドレスレジスタ
	reg					PCI_IDSEL ;							// IDSELレジスタ

// ローカルバスシーケンサ スタートフラグ
	reg					LOCAL_Bus_Start ;
// ローカルバスシーケンサ データ転送完了フラグ
	reg					LOCAL_DTACK ;

// トライステートバッファ制御用のフリップフロップ定義 //
	// PCIバス信号線
	wire				REQ_HiZ ;  
	wire				REQ_Port ;		
	reg					PCIAD_HiZ ;							// ADポート出力ドライブ制御(ターゲット用)
	reg			[31:0]	PCIAD_Port ;						// ADポート出力レジスタ(ターゲット用)
	reg					DEVSEL_HiZ, DEVSEL_Port ;			// DEVSEL#出力ドライブ制御/出力レジスタ
	reg					TRDY_HiZ, TRDY_Port    ;			// TRDY#出力ドライブ制御/出力レジスタ
	reg					INTA_HiZ			   ;			// INTA#出力ドライブ制御/出力レジスタ
	wire				INTA_Port ;
	reg					PAR_HiZ,  PAR_Port     ;			// PAR出力ドライブ制御/出力レジスタ
	reg					STOP_HiZ, STOP_Port    ;			// STOP出力ドライブ制御/出力レジスタ

	wire				PERR_HiZ, PERR_Port    ;			// ダミーノード(ターゲット7未使用)
	wire				SERR_HiZ, SERR_Port    ;
	wire				INTB_HiZ, INTB_Port    ;
	wire				INTC_HiZ, INTC_Port    ;
	wire				INTD_HiZ, INTD_Port    ;

//  PCIバスコマンド(ビットパターン定義) //
	// コンフィギュレーションサイクル
	parameter			PCI_CfgCycle      = 3'b101;
	parameter			PCI_CfgReadCycle  = 4'b1010;
	parameter			PCI_CfgWriteCycle = 4'b1011;
	// メモリサイクル
	parameter			PCI_MemCycle      = 3'b011;
	parameter			PCI_MemReadCycle  = 4'b0110;
	parameter			PCI_MemWriteCycle = 4'b0111;
	// I/Oサイクル
	parameter			PCI_IoCycle       = 3'b001;
	parameter			PCI_IoReadCycle   = 4'b0010;
	parameter			PCI_IoWriteCycle  = 4'b0011;

// コンフィギュレーションレジスタ群(読み出し専用レジスタ) //
	parameter			CFG_VendorID	= 16'h6809;				// ベンダID   6809h
	parameter			CFG_DeviceID	= 16'h8000;				// デバイスID 8000h
	parameter			CFG_Command		= 16'h0000;
	parameter			CFG_Status		= 16'h0200;				// DEVSEL# 中速応答
	parameter			CFG_BaseClass	= 8'h05;				// 05h RAM
	parameter			CFG_SubClass	= 8'h00;
	parameter			CFG_ProgramIF	= 8'h00;
	parameter			CFG_RevisionID	= 8'h01;				// レビジョン 1
	parameter			CFG_HeaderType	= 8'h00;				// ヘッダタイプ0
	parameter			CFG_Int_Pin   	= 8'h01;				// INTA#のみ使用

// コンフィギュレーションレジスタ群(読み書きレジスタ) //
	// コマンドレジスタ メモリイネーブルビット
	reg					CFG_Cmd_Mem ;
	// コマンドレジスタ I/Oイネーブルビット
	reg					CFG_Cmd_Io ;
	// コマンドレジスタ 割り込みディセーブルビット
	reg					CFG_Cmd_IntDis ;
	// ステータスレジスタ 割り込みステータスビット
	reg					CFG_Sta_IntSta ;
	// ベースアドレスレジスタ(メモリ空間)
	reg			[31:24]	CFG_Base_Addr0 ;
	// ベースアドレスレジスタ(I/O空間)
	reg			[15:2]	CFG_Base_Addr1 ;
	// インタラプトラインレジスタ
	reg			[7:0]	CFG_Int_Line ;

// アドレスデコードフラグ
	wire				Hit_Device ;	// デバイスヒット
	reg					Hit_Memory ;	// メモリサイクルヒット
	reg					Hit_Io ;		// I/Oサイクルヒット
	reg					Hit_Config ;	// コンフィグレーションサイクルヒット

// PCIADバスドライブ時パリティ計算
// ターゲット パリティ生成 //
	wire				TGT_temp_PAR_DB ;	// テンポラリ
	wire				TGT_temp_PAR_CBE ;	// テンポラリ
	wire				TGT_PAR   ;			// ターゲット用

// ローカルバス トライステート制御
	reg					MEM_DATA_HiZ  ;	// メモリデータバストライステート制御
	reg			[31:0]	MEM_DATA_Port ;	// メモリデータバス

// メモリアクセス ウェイトカウンタ
	reg			[3:0]	WAIT_Count ;

//  割り込み制御レジスタ群
	// 割り込みステータス/フラグレジスタ
	reg					INT_STAT3 ;
	reg					INT_STAT2 ;
	reg					INT_STAT1 ;
	reg					INT_STAT0 ;
	// 割り込みマスク(許可)レジスタ
	reg					INT_MSK3 ;
	reg					INT_MSK2 ;
	reg					INT_MSK1 ;
	reg					INT_MSK0 ;
	// 割り込みステータスクリア指示レジスタ
	reg					INT_CLR3 ;
	reg					INT_CLR2 ;
	reg					INT_CLR1 ;
	reg					INT_CLR0 ;
	// 割り込み入力状態保存フラグ
	reg					INT_IN3_flg1 ;
	reg					INT_IN2_flg1 ;
	reg					INT_IN1_flg1 ;
	reg					INT_IN0_flg1 ;
	reg					INT_IN3_flg0 ;
	reg					INT_IN2_flg0 ;
	reg					INT_IN1_flg0 ;
	reg					INT_IN0_flg0 ;

// PCIターゲットシーケンサ ステートバリューレジスタ //
	reg			[2:0]	PCI_TGT_NEXT_STATE ;

// PCIターゲットシーケンサ ステートマシン定義
	parameter			BUS_IDLE		 = 3'b000;
	parameter			ADRS_COMPARE	 = 3'b001;
	parameter			BUS_BUSY		 = 3'b010;
	parameter			WAIT_IRDY		 = 3'b011;
	parameter			WAIT_LOCAL_ACK	 = 3'b100;
	parameter			ACC_COMPLETE	 = 3'b101;
	parameter			DIS_CONNECT		 = 3'b110;
	parameter			TGT_TURN_AROUND	 = 3'b111;

// ローカルバスシーケンサ ステートバリューレジスタ //
	reg			[2:0]	LOCAL_NEXT_STATE ;				// 次のステート

// ローカルバスシーケンサ ステートマシン定義
	parameter			LOCAL_IDLE		 = 3'b000 ,
						LOCAL_CFG_ACCESS = 3'b001 ,
						LOCAL_MEM_ACCESS = 3'b010 ,
						LOCAL_IO_ACCESS  = 3'b011 ,
						LOCAL_STATE_COMP = 3'b111 ;


// ************************************************************************* //
// **********	同時処理文
// ************************************************************************* //

// トライステートバッファ動作(PCIバスサイド）
	assign	#tPD	PCIAD		= ( PCIAD_HiZ ) ? {32{1'bz}} : PCIAD_Port;

	assign	#tPD	DEVSEL_n	= ( DEVSEL_HiZ ) ? 1'bz : DEVSEL_Port;
	assign	#tPD	TRDY_n  	= ( TRDY_HiZ ) ? 1'bz : TRDY_Port;
	assign	#tPD	STOP_n		= ( STOP_HiZ ) ? 1'bz : STOP_Port;

	assign	#tPD	INTA_n		= ( INTA_HiZ ) ? 1'bz : INTA_Port;
	assign	#tPD	INTA_Port	= 1'b0 ;

	assign	#tPD	PAR   		= ( PAR_HiZ ) ? 1'bz : PAR_Port;

// トライステートバッファ動作(SRAMバスサイド）
	assign	#tPD	MEM_ADRS[23:0] = { PCI_Address[23:2] , 2'b00 } ;
	assign	#tPD	MEM_DATA[31:0] = ( MEM_DATA_HiZ ) ? 32'bz : MEM_DATA_Port ;

// 未使用ピンの状態設定(ハイインピーダンス状態に固定)
	assign	#tPD	REQ_n 		= ( REQ_HiZ ) ? 1'bz : REQ_Port;
	assign	#tPD	REQ_HiZ		= 1'b0;
	assign	#tPD	REQ_Port	= 1'b1;

	assign	#tPD	PERR_n		= ( PERR_HiZ ) ? 1'bz : PERR_Port;
	assign	#tPD	PERR_HiZ	= 1'b1;
	assign	#tPD	PERR_Port	= 1'b0;

	assign	#tPD	SERR_n		= ( SERR_HiZ ) ? 1'bz : SERR_Port;
	assign	#tPD	SERR_HiZ	= 1'b1;
	assign	#tPD	SERR_Port	= 1'b0;

	assign	#tPD	INTB_n		= ( INTB_HiZ ) ? 1'bz : INTB_Port;
	assign	#tPD	INTB_HiZ	= 1'b1;
	assign	#tPD	INTB_Port	= 1'b0;

	assign	#tPD	INTC_n		= ( INTC_HiZ ) ? 1'bz : INTC_Port;
	assign	#tPD	INTC_HiZ	= 1'b1;
	assign	#tPD	INTC_Port	= 1'b0;

	assign	#tPD	INTD_n		= ( INTD_HiZ ) ? 1'bz : INTD_Port;
	assign	#tPD	INTD_HiZ	= 1'b1;
	assign	#tPD	INTD_Port	= 1'b0;



// ************************************************************************* //
// **********	PCIターゲットシーケンサ
// ************************************************************************* //

//PCI_TGT_Seq
always @(posedge PCICLK or negedge RST_n)

begin

// ********** リセット時動作 ********** //
	if (RST_n == 1'b0) begin	// PCIバスリセット時(非同期リセット)

		PCI_TGT_NEXT_STATE		<= BUS_IDLE;	// ステートマシン IDLE状態 リセット

		LOCAL_Bus_Start <= 1'b0;		// ローカルバスシーケンサ スタートフラグ クリア

		PCI_BusCommand	<= 4'b0000 ;			// PCIバスコマンドレジスタ クリア
		PCI_Address		<= 32'h00000000 ;		// PCIバスアドレスレジスタ クリア
		PCI_IDSEL		<= 1'b0;				// IDSELレジスタ クリア

	// 制御出力端子をハイインピーダンス
		PCIAD_HiZ <= 1'b1;
		DEVSEL_HiZ <= 1'b1; DEVSEL_Port <= 1'b1;	// DEVSEL#="H"
		TRDY_HiZ   <= 1'b1; TRDY_Port   <= 1'b1;	// TRDY#="H"
		STOP_HiZ   <= 1'b1; STOP_Port   <= 1'b1;	// STOP#="H"


// ********** PCIターゲットシーケンサ ステートマシン ********** //
	end else begin

		case ( PCI_TGT_NEXT_STATE )

	// ********** BUS_IDLE時の動作 ********** //
		BUS_IDLE : begin	// トランザクションの開始待ち

			if (FRAME_n == 1'b0 & IRDY_n == 1'b1) begin	// トランザクション開始
				PCI_BusCommand <= C_BE_n;	// PCIバスコマンド取得
				PCI_Address <= PCIAD;		// アドレス取得
				PCI_IDSEL <= IDSEL;			// IDSEL取得
				PCI_TGT_NEXT_STATE <= ADRS_COMPARE;
			end else begin	// バスアイドル時このステートにとどまる
				PCI_TGT_NEXT_STATE <= BUS_IDLE;
			end
   		end

	// ********** ADRS_COMPARE時の動作 ********** //
		ADRS_COMPARE : begin	// アドレスデコード結果を調べる

			if (Hit_Device == 1'b1) begin	// 自分が選択された
				DEVSEL_Port <= 1'b0; DEVSEL_HiZ <= 1'b0;	// DEVLSEL#アサート
				TRDY_HiZ <= 1'b0;	// TRDY# を "H"にドライブ
				STOP_HiZ <= 1'b0;	// STOP# を "H"にドライブ
				PCI_TGT_NEXT_STATE <= WAIT_IRDY;	// イニシエータレディを待つステートへ

			end else begin	// 自分が選択されていない
				PCI_TGT_NEXT_STATE <= BUS_BUSY;	// トランザクションの終了を待つステートへ
			end
		end

	// ********** BUS_BUSY時の動作 ********** //
		BUS_BUSY : begin	// トランザクション終了待ち

			if (FRAME_n == 1'b1 & IRDY_n == 1'b1) begin	// トランザクション終了(アイドル)
				PCI_TGT_NEXT_STATE <= BUS_IDLE;	// トランザクション開始待ちステートへ

			end else begin	// トランザクション中ならこのステートにとどまる
				PCI_TGT_NEXT_STATE <= BUS_BUSY;
			end
		end

	// ********** WAIT_IRDY時の動作 ********** //
		WAIT_IRDY : begin	// イニシエータレディ待ち

			if (IRDY_n == 1'b0) begin	// イニシエータの準備完了
				if (PCI_BusCommand[0] == 1'b0) begin	// リードサイクルのとき
					PCIAD_HiZ <= 1'b0;				// PCIAD[31:0]バスドライブ
				end
				LOCAL_Bus_Start <= 1'b1;	// ローカルバスシーケンサ スタート!
				PCI_TGT_NEXT_STATE <= WAIT_LOCAL_ACK;	// ローカルバスシーケンサ終了待ちステートへ

			end else begin	// イニシエータの準備がまだならこのステートにとどまる
				PCI_TGT_NEXT_STATE <= WAIT_IRDY;
			end
		end

	// ********** WAIT_LOCAL_ACK時の動作 ********** //
		WAIT_LOCAL_ACK : begin	// ローカルバスシーケンサ終了待ち

			LOCAL_Bus_Start <= 1'b0;	// ローカルバスシーケンサ スタートフラグ クリア

			if (LOCAL_DTACK == 1'b1) begin	// ローカルバスシーケンサ データ転送完了
				TRDY_Port <= 1'b0;	// TRDY# アサート
				STOP_Port <= 1'b0;	// STOP# アサート
				PCI_TGT_NEXT_STATE <= ACC_COMPLETE;	// アクセス完了ステートへ

			end else begin	// ローカルバスシーケンサの準備がまだならこのステートにとどまる
				PCI_TGT_NEXT_STATE <= WAIT_LOCAL_ACK;
			end
		end

	// ********** ACC_COMPLETE時の動作 ********** //
		ACC_COMPLETE : begin	// アクセス完了ステート

			TRDY_Port <= 1'b1;		// TRDY# ディアサート
			PCIAD_HiZ <= 1'b1;		// PCIAD[31:0]バスドライブ解放

			if (FRAME_n == 1'b0) begin			// FRAME# = 'L'ならバースト転送要求
				PCI_TGT_NEXT_STATE <= DIS_CONNECT;	// ディスコネクトステートへ

			end else begin	// 単一データフェーズのトランザクションの時
				DEVSEL_Port <= 1'b1;		// DEVSEL#ディアサート
				STOP_Port   <= 1'b1;		// STOP#ディアサート
				PCI_TGT_NEXT_STATE <= TGT_TURN_AROUND;	//  ターンアラウンドステートへ
			end
		end

	// ********** DIS_CONNECT時の動作 ********** //
		DIS_CONNECT : begin		// ディスコネクト処理

			if (FRAME_n == 1'b1) begin	// イニシエータがSTOP#を認識
				DEVSEL_Port <= 1'b1;	// DEVSEL# ディアサート
				STOP_Port <= 1'b1;	// STOP# ディアサート
				PCI_TGT_NEXT_STATE <= TGT_TURN_AROUND;	// 次はTGT_TURN_AROUNDステートへ

			end else begin	// イニシエータがSTOP#を認識していなければこのステートにとどまる
				PCI_TGT_NEXT_STATE <= DIS_CONNECT;
			end
		end

	// ********** TGT_TURN_AROUND時の動作 ********** //
		TGT_TURN_AROUND : begin		// ターンアラウンドステート

			DEVSEL_HiZ <= 1'b1;			// DEVSEL#ドライブ解放
			TRDY_HiZ <= 1'b1;			// TRDY#ドライブ解放
			STOP_HiZ <= 1'b1;			// STOP#ドライブ解放
			PCI_TGT_NEXT_STATE <= BUS_IDLE;	// トランザクション開始待ちステートへ
		end

	// ****************************************** //
		default : begin					// これ以外の値では何もしない場合でも必ず入れる
			PCI_TGT_NEXT_STATE <= TGT_TURN_AROUND;	// 次はTGT_TURN_AROUNDステートへ
		end

	endcase

	end

end	//PCI_TGT_Seq;



// ************************************************************************* //
// **********	ローカルバスシーケンサ
// ************************************************************************* //


//LOCAL_BUS_Seq
always @(posedge PCICLK or negedge RST_n)

begin

// ********** リセット時動作 ********** //
	if (RST_n == 1'b0) begin	// PCIバスリセットがアサートされたとき

		// ステートバリューレジスタクリア
		LOCAL_NEXT_STATE <= 0;	// ローカルバスシーケンサ リセット

		// コンフィグレーションレジスタ リード/ライトレジスタ インタラプトライン クリア
//		CFG_Cmd_Mem <= 1'b0;
		CFG_Cmd_Mem <= 1'b1;
		CFG_Cmd_Io <= 1'b0;
		CFG_Cmd_IntDis <= 1'b0;
//		CFG_Base_Addr0 <= 0 ;
		CFG_Base_Addr0 <= 32'hf0000000 ;
		CFG_Base_Addr1 <= 0 ;
		CFG_Int_Line <= 0;

		// ローカルバス制御線ディセーブル
		MEM_CEn  <= 1'b1;		// SRAM0〜3 /CE
		MEM_OEn  <= 1'b1;		// SRAM0〜3 /OE
		MEM_WE0n <= 1'b1;		// SRAM0 /WE
		MEM_WE1n <= 1'b1;		// SRAM1 /WE
		MEM_WE2n <= 1'b1;		// SRAM2 /WE
		MEM_WE3n <= 1'b1;		// SRAM3 /WE
		MEM_DATA_HiZ  <= 1'b0;	// データバス出力方向

		PCIAD_Port <= 0 ;		// AD出力レジスタ クリア
		MEM_DATA_Port <= 0 ;	// MEM_DATA出力レジスタ クリア

		// メモリアクセス ウェイトカウンタ クリア
		WAIT_Count <= 0 ;

		// ローカルバスシーケンサ データ転送完了フラグ クリア
		LOCAL_DTACK <= 1'b0;

		// 割り込み制御レジスタ
		INT_MSK3 <= 1'b0;	// 割り込みマスクレジスタ クリア
		INT_MSK2 <= 1'b0;
		INT_MSK1 <= 1'b0;
		INT_MSK0 <= 1'b0;
		INT_CLR3 <= 1'b0;	// 割り込みステータスクリア指示信号 クリア
		INT_CLR2 <= 1'b0;
		INT_CLR1 <= 1'b0;
		INT_CLR0 <= 1'b0;


// ********** ローカルバスシーケンサ ステートマシン ********** //
	end else begin

		case ( LOCAL_NEXT_STATE )

	// ********** LOCAL_IDLE時の動作 ********** //
		LOCAL_IDLE : begin	// ローカルバスシーケンサ スタート指示待ち

			if (LOCAL_Bus_Start == 1'b1 ) begin	// ローカルバスシーケンサ スタート!

				if (Hit_Config == 1'b1) begin	// コンフィグレーションサイクルヒット
					LOCAL_NEXT_STATE <= LOCAL_CFG_ACCESS;	// コンフィグレーションステートへ
				end
				if (Hit_Memory == 1'b1) begin	// メモリサイクルヒット
					LOCAL_NEXT_STATE <= LOCAL_MEM_ACCESS;	// メモリアクセスステートへ
				end
				if (Hit_Io == 1'b1) begin		// I/Oサイクルヒット
					LOCAL_NEXT_STATE <= LOCAL_IO_ACCESS;	// I/Oアクセスステートへ
				end

			end else begin	// ローカルバスシーケンサ スタートフラグがまだならこのステートにとどまる

				LOCAL_NEXT_STATE <= LOCAL_IDLE;
			end
		end

	// ********** LOCAL_MEM_ACCESS時の動作 ********** //
		LOCAL_MEM_ACCESS : begin

			case ( WAIT_Count )
				4'b0000 : begin		// ウェイトカウンタ0クロック目
					MEM_CEn <= 1'b0;						// SRAM /CE アサート
					if (PCI_BusCommand[0] == 1'b1) begin	// メモリライトサイクル
						MEM_DATA_Port <= PCIAD;				// ライトデータ
					end else begin							// メモリリードサイクル
						MEM_DATA_HiZ <= 1'b1;				// ローカルデータバス入力方向
					end
					LOCAL_NEXT_STATE <= LOCAL_MEM_ACCESS;	// メモリアクセスはまだ終わらない
				end

				4'b0001 : begin		// ウェイトカウンタ1クロック目
					if (PCI_BusCommand[0] == 1'b1) begin		// メモリライトサイクル
						MEM_WE3n <= C_BE_n[3];				// バイトイネーブルを/WEに出力
						MEM_WE2n <= C_BE_n[2];
						MEM_WE1n <= C_BE_n[1];
						MEM_WE0n <= C_BE_n[0];
					end else begin							// メモリリードサイクル
						MEM_OEn <= 1'b0;					// SRAM /OE アサート
					end
					LOCAL_NEXT_STATE <= LOCAL_MEM_ACCESS;	// メモリアクセスはまだ終わらない
				end

				4'b0100 : begin		// ウェイトカウンタ4クロック目
					if (PCI_BusCommand[0] == 1'b1) begin	// メモリライトサイクル
						MEM_WE3n <= 1'b1;					// SRAM /WE ディセーブル
						MEM_WE2n <= 1'b1;
						MEM_WE1n <= 1'b1;
						MEM_WE0n <= 1'b1;
					end else begin							// メモリリードサイクル
						PCIAD_Port <= MEM_DATA;				// SRAMデータをADバスに出力
						MEM_OEn <= 1'b1;					// SRAM /OE ディアサート
					end
					LOCAL_DTACK <= 1'b1;					// ローカルバスシーケンサ データ転送完了フラグ セット
					LOCAL_NEXT_STATE <= LOCAL_STATE_COMP;	// メモリアクセス完了
				end

				default : begin			// そのままの状態でウェイト時間が経過するのを待つ
					LOCAL_NEXT_STATE <= LOCAL_MEM_ACCESS;	// メモリアクセスはまだ終わらない
				end
			endcase

			WAIT_Count <= WAIT_Count + 1 ;	// ウェイトカウント + 1

		end


	// ********** LOCAL_IO_ACCESS時の動作 ********** //
		LOCAL_IO_ACCESS : begin

			if (PCI_BusCommand[0] == 1'b1 ) begin	// ライトサイクル

				case ( PCI_Address[1:0] )
					2'b00 : begin				// 割り込みステータスレジスタへのアクセス
						INT_CLR3 <= PCIAD[3];		// ステータスクリア #3
						INT_CLR2 <= PCIAD[2];		// ステータスクリア #2
						INT_CLR1 <= PCIAD[1];		// ステータスクリア #1
						INT_CLR0 <= PCIAD[0];		// ステータスクリア #0
					end
					2'b10 : begin				// 割り込みマスクレジスタへのアクセス
						INT_MSK3 <= PCIAD[19];		// 割り込みマスク #3
						INT_MSK2 <= PCIAD[18];		// 割り込みマスク #2
						INT_MSK1 <= PCIAD[17];		// 割り込みマスク #1
						INT_MSK0 <= PCIAD[16];		// 割り込みマスク #0
					end
				endcase

			end else begin	// リードサイクル

				case ( PCI_Address[1:0] )
					2'b00 : begin				// 割り込みステータスレジスタへのアクセス
						PCIAD_Port[31:4]	<= 0 ;
						PCIAD_Port[3]		<= INT_STAT3;// 割り込み3ステータス
						PCIAD_Port[2]		<= INT_STAT2;// 割り込み2ステータス
						PCIAD_Port[1]		<= INT_STAT1;// 割り込み1ステータス
						PCIAD_Port[0]		<= INT_STAT0;// 割り込み0ステータス
					end
					2'b10 : begin				// 割り込みマスクレジスタへのアクセス
						PCIAD_Port[31:20]	<= 0 ;
						PCIAD_Port[19]		<= INT_MSK3;	// 割り込み3マスク
						PCIAD_Port[18]		<= INT_MSK2;	// 割り込み2マスク
						PCIAD_Port[17]		<= INT_MSK1;	// 割り込み1マスク
						PCIAD_Port[16]		<= INT_MSK0;	// 割り込み0マスク
						PCIAD_Port[15:0]	<= 0 ;
					end
					default : begin				// それ以外のアクセスは0を返す
						PCIAD_Port[31:0]		<= 32'h00000000 ;
					end
				endcase

			end

			LOCAL_DTACK <= 1'b1;		// ローカルバスシーケンサ データ転送完了フラグ セット
			LOCAL_NEXT_STATE <= LOCAL_STATE_COMP;
		end


	// ********** LOCAL_CFG_ACCESS時の動作 ********** //
		LOCAL_CFG_ACCESS : begin	// コンフィグレーションサイクル

			if  (PCI_BusCommand[0] ) begin			// コンフィグレーションライトサイクル

				case ( PCI_Address[7:2] )

				6'b000001 : begin	// コマンド/ステータスレジスタ
					if (C_BE_n[1] == 1'b0) begin
						CFG_Cmd_IntDis <= PCIAD[10];// 割り込みディセーブル
					end
					if (C_BE_n[0] == 1'b0) begin
						CFG_Cmd_Mem <= PCIAD[1];	// メモリイネーブル
						CFG_Cmd_Io  <= PCIAD[0];	// I/Oイネーブル
					end
				end

				6'b000100 : begin	// ベースアドレスレジスタ0
					if (C_BE_n[3] == 1'b0) begin
						CFG_Base_Addr0[31:24] <= PCIAD[31:24];
					end
				end

				6'b000101 : begin	// ベースアドレスレジスタ1
					if (C_BE_n[1] == 1'b0) begin
						CFG_Base_Addr1[15:8] <= PCIAD[15:8];
					end
					if (C_BE_n[0] == 1'b0) begin
						CFG_Base_Addr1[7:2] <= PCIAD[7:2];
					end
				end

				6'b001111 : begin	// 割り込みラインレジスタ
					if (C_BE_n[0] == 1'b0) begin
						CFG_Int_Line[7:0] <= PCIAD[7:0];
					end
				end

				endcase


			end else begin	// コンフィグレーションリードサイクル

				case ( PCI_Address[7:2] )

				6'b000000 : begin	// ベンダID/デバイスID
					PCIAD_Port[31:16]		<= CFG_DeviceID;
					PCIAD_Port[15:0]		<= CFG_VendorID;
				end

				6'b000001 : begin	// コマンド/ステータスレジスタ
					PCIAD_Port[31:20]		<= CFG_Status[15:4];
					PCIAD_Port[19]          <= CFG_Sta_IntSta;
					PCIAD_Port[18:16]		<= CFG_Status[2:0];
					PCIAD_Port[15:11]		<= CFG_Command[15:11];
					PCIAD_Port[10]          <= CFG_Cmd_IntDis;
					PCIAD_Port[9:2]			<= CFG_Command[9:2];
					PCIAD_Port[1]           <= CFG_Cmd_Mem;
					PCIAD_Port[0]			<= CFG_Cmd_Io;
				end

				6'b000010 : begin	// クラスコード
					PCIAD_Port[31:24]		<= CFG_BaseClass;
					PCIAD_Port[23:16]		<= CFG_SubClass;
					PCIAD_Port[15: 8]		<= CFG_ProgramIF;
					PCIAD_Port[ 7: 0]		<= CFG_RevisionID;
				end

				6'b000011 : begin	// ヘッダタイプほか
					PCIAD_Port[31:24]		<= 8'b0 ;
					PCIAD_Port[23:16]		<= CFG_HeaderType;
					PCIAD_Port[15: 0]		<= 16'b0 ;
				end

				6'b000100 : begin	// ベースアドレスレジスタ0
					PCIAD_Port[31:24]		<= CFG_Base_Addr0;
					PCIAD_Port[23: 0]		<= 24'b0 ;
				end

				6'b000101 : begin	// ベースアドレスレジスタ1
					PCIAD_Port[31:16]		<= 24'b0 ;
					PCIAD_Port[15: 2]		<= CFG_Base_Addr1;
					PCIAD_Port[1]			<= 1'b0 ;
					PCIAD_Port[0]			<= 1'b1 ;
				end

				6'b001011 : begin	// サブシステムベンダID/サブシステムID
					PCIAD_Port[31:16]		<= CFG_DeviceID;
					PCIAD_Port[15: 0]		<= CFG_VendorID;
				end

				6'b001111 : begin	// 割り込み関連レジスタ
					PCIAD_Port[31:16]		<= 16'b0 ;
					PCIAD_Port[15 :8]		<= CFG_Int_Pin;
					PCIAD_Port[ 7: 0]		<= CFG_Int_Line;
				end

				default : begin // その他のレジスタ
					PCIAD_Port <= 32'h0 ;			// すべて0を返す
				end

				endcase

			end

			LOCAL_DTACK <= 1'b1;		// ローカルバスシーケンサ データ転送完了フラグ セット
			LOCAL_NEXT_STATE <= LOCAL_STATE_COMP;
		end


	// ********** LOCAL_STATE_COMP時の動作 ********** //
		LOCAL_STATE_COMP : begin	// ローカルバスアクセス完了

			INT_CLR3 <= 1'b0;		// 割り込みクリア指示信号クリア
			INT_CLR2 <= 1'b0;
			INT_CLR1 <= 1'b0;
			INT_CLR0 <= 1'b0;

			MEM_CEn <= 1'b1;		// SRAM /CE ディアサート
			MEM_DATA_HiZ <= 1'b0;	// ローカルデータバス出力方向
			WAIT_Count <= 0;

			LOCAL_DTACK <= 1'b0;		// ローカルバスシーケンサ データ転送完了フラグ クリア
			LOCAL_NEXT_STATE <= LOCAL_IDLE;
		end


	// ********************************************** //
		default : begin					// これ以外の値では何もしない場合でも必ず入れる
			LOCAL_NEXT_STATE <= LOCAL_IDLE;
		end

		endcase

	end

end //LOCAL_BUS_Seq;



// ************************************************************************* //
// **********	割り込みコントローラ
// ************************************************************************* //
//INT_Ctrl
always @(posedge PCICLK or negedge RST_n)
begin
	if ( ~RST_n  ) begin	// PCIバスリセットがアサートされたとき

		INTA_HiZ  		<= 1'b1;	// INTA# ハイインピーダンス
		CFG_Sta_IntSta	<= 1'b0;

		INT_STAT3	 <= 1'b0;	// 割り込み要求レジスタ クリア
		INT_STAT2	 <= 1'b0;
		INT_STAT1	 <= 1'b0;
		INT_STAT0	 <= 1'b0;
		INT_IN3_flg1 <= 1'b0;	// 割り込み入力フラグ クリア
		INT_IN2_flg1 <= 1'b0;
		INT_IN1_flg1 <= 1'b0;
		INT_IN0_flg1 <= 1'b0;
		INT_IN3_flg0 <= 1'b0;
		INT_IN2_flg0 <= 1'b0;
		INT_IN1_flg0 <= 1'b0;
		INT_IN0_flg0 <= 1'b0;

	end else begin

	// **********	コンフィグレーションステータスレジスタ アボートビット制御	 ********** //
		if (INT_CLR3 == 1'b1) begin
			INT_STAT3  <= 1'b0;	// 割り込みステータスレジスタ3クリア
		end else begin
			if (INT_IN3_flg1 == 1'b1 & INT_IN3_flg0 == 1'b0) begin	// 外部割り込み入力3 立ち下りエッジ
				INT_STAT3  <= 1'b1;	// 割り込みステータスレジスタ3
			end
		end
		if (INT_CLR2 == 1'b1) begin
			INT_STAT2  <= 1'b0;	// 割り込みステータスレジスタ2クリア
		end else begin
			if (INT_IN2_flg1 == 1'b1 & INT_IN2_flg0 == 1'b0) begin	// 外部割り込み入力2 立ち下りエッジ
				INT_STAT2  <= 1'b1;	// 割り込みステータスレジスタ2
			end
		end
		if (INT_CLR1 == 1'b1) begin
			INT_STAT1  <= 1'b0;	// 割り込みステータスレジスタ1クリア
		end else begin
			if (INT_IN1_flg1 == 1'b1 & INT_IN1_flg0 == 1'b0) begin	// 外部割り込み入力1 立ち下りエッジ
				INT_STAT1  <= 1'b1;	// 割り込みステータスレジスタ1
			end
		end
		if (INT_CLR0 == 1'b1) begin
			INT_STAT0  <= 1'b0;	// 割り込みステータスレジスタ0クリア
		end else begin
			if (INT_IN0_flg1 == 1'b1 & INT_IN0_flg0 == 1'b0) begin	// 外部割り込み入力0 立ち下りエッジ
				INT_STAT0  <= 1'b1;	// 割り込みステータスレジスタ0
			end
		end

										// 割り込みディセーブルビットがセットされていない
										// 割り込みマスク解除時割り込み発生
		if ( ~CFG_Cmd_IntDis & 
			(
				(INT_STAT3 == 1'b1 & INT_MSK3 == 1'b1) // チャネル3割り込み発生&割り込み可
				|
				(INT_STAT2 == 1'b1 & INT_MSK2 == 1'b1) // チャネル2割り込み発生&割り込み可
				|
				(INT_STAT1 == 1'b1 & INT_MSK1 == 1'b1) // チャネル1割り込み発生&割り込み可
				|
				(INT_STAT0 == 1'b1 & INT_MSK0 == 1'b1) // チャネル0割り込み発生&割り込み可
			)
		) begin
			INTA_HiZ <= 1'b0;	// INTA#ドライブ開始(アサート)
			CFG_Sta_IntSta <= 1'b1;	// 割り込み出力中
		end else begin
			INTA_HiZ <= 1'b1;	// ハイインピーダンス状態
			CFG_Sta_IntSta <= 1'b0;
		end

		INT_IN3_flg1 <= INT_IN3_flg0;
		INT_IN2_flg1 <= INT_IN2_flg0;
		INT_IN1_flg1 <= INT_IN1_flg0;
		INT_IN0_flg1 <= INT_IN0_flg0;
		INT_IN3_flg0 <= INT_IN3;	// 現在の割り込み入力状態の保存
		INT_IN2_flg0 <= INT_IN2;
		INT_IN1_flg0 <= INT_IN1;
		INT_IN0_flg0 <= INT_IN0;

	end

end //INT_Ctrl;



// ************************************************************************* //
// **********	アドレスデコーダ
// ************************************************************************* //

// メモリサイクルorコンフィグレーションサイクルヒット = 自分が選択されている
	assign	#tPD	Hit_Device = Hit_Memory | Hit_Config | Hit_Io;

//Address_Decoder
always @*
/*	(
		PCI_IDSEL,		// コンフィグレーションデバイスセレクト
		PCI_Address,	// PCIバスアドレス
		PCI_BusCommand,	// バスコマンド
		CFG_Base_Addr0,	// ベースアドレスレジスタ0
		CFG_Base_Addr1,	// ベースアドレスレジスタ1
		CFG_Cmd_Mem,	// コンフィグレーションレジスタ メモリイネーブルビット
		CFG_Cmd_Io		// コンフィグレーションレジスタ I/Oイネーブルビット
	)*/
begin

	// メモリ空間へのアクセスアドレスとベースアドレス0が一致したか
	if (
		(
			PCI_BusCommand[3:1] == PCI_MemCycle	// メモリサイクル
		) & (
			PCI_Address[31:24] == CFG_Base_Addr0	// ベースアドレス0と比較
		) & (
			CFG_Cmd_Mem == 1'b1	// コンフィグレーション コマンドレジスタ メモリイネーブルビット
		)
	) begin
		Hit_Memory <= 1'b1;	// メモリサイクルヒット
	end else begin
		Hit_Memory <= 1'b0;
	end

	// I/O空間へのアクセスアドレスとベースアドレス1が一致したか
	if (
		(
			PCI_BusCommand[3:1] == PCI_IoCycle	// I/Oサイクル
		) & (
			PCI_Address[31:16] == 0				// 上位16ビットが0か
		) & (
			PCI_Address[15:2] == CFG_Base_Addr1	// ベースアドレス1と比較
		) & (
			CFG_Cmd_Io == 1'b1	// コンフィグレーション コマンドレジスタ I/Oイネーブルビット
		)
	) begin
		Hit_Io <= 1'b1;	// I/Oサイクルヒット
	end else begin
		Hit_Io <= 1'b0;
	end

	// コンフィグレーション空間へのアクセスかどうかを認識
	if (
		(
			PCI_BusCommand[3:1] == PCI_CfgCycle	// コンフィグレーションサイクル
		) & (
			PCI_IDSEL == 1'b1		// 自分が選択されているか
		) & (
			PCI_Address[10: 8] == 3'b000	// ファンクション番号0のみ
		) & (
			PCI_Address[ 1: 0] == 2'b00		// タイプ0のみ
		)
	) begin
		Hit_Config <= 1'b1;	// コンフィグレーションサイクルヒット
	end else begin
		Hit_Config <= 1'b0;
	end

end //Address_Decoder;


// ************************************************************************* //
// **********	パリティジェネレータ
// ************************************************************************* //

// ***** パリティ生成 ***** //
//PCI_Parity_Gen
	// ターゲット パリティ生成 //
	assign			TGT_temp_PAR_DB  = ^PCIAD_Port ;
	assign			TGT_temp_PAR_CBE = ^C_BE_n ;
	assign	#tPD	TGT_PAR = TGT_temp_PAR_DB ^ TGT_temp_PAR_CBE ;

// ***** パリティ出力制御 ***** //
//PCI_Parity_Ctrl
always @(posedge PCICLK or negedge RST_n)
begin
	if ( ~RST_n ) begin
		PAR_HiZ  <= 1'b1;
		PAR_Port <= 1'b0;
	end else begin
		if ( PCIAD_HiZ == 1'b0) begin	// パリティ出力イネーブルの制御
			PAR_HiZ  <= 1'b0;
			PAR_Port <= TGT_PAR;
		end else begin
			PAR_HiZ  <= 1'b1;
		end
		// ↑ADバスのドライブから1クロック遅れてPARを制御
	end
end	//PCI_Parity_Ctrl;


endmodule
