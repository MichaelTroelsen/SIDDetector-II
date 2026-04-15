/*
** Arm2SID tester/configurator using cc65
**
** Bohumil Novacek (dzin@post.cz)
**
*/

#include <stdlib.h>
#include <conio.h>

#define CHAR_N	'n'
#define CHAR_O	'o'
#define CHAR_S	's'
#define CHAR_W	'w'
#define CHAR_A	'a'
#define CHAR_L	'l'
#define CHAR_R	'r'
#define CHAR_E	'e'
#define CHAR_B	'b'

/*****************************************************************************/
/*                                   Data                                    */
/*****************************************************************************/

static const char Nadpis [] = "\\\\       nobomi armsid tester v3.12\\\\\\";
static const char Notfou [] = "armsid not found";
static const char * Founda [3] = { "armsid" , "arm2sid left channel" , "arm2sid right channel" };
static const char WarnBL 	 [] = "!! warning ! bootloader fw  ! warning !!";
static const char WarnBeta [] = "!! warning ! beta firmware  ! warning !!";

/*****************************************************************************/
/*                                   Code                                    */
/*****************************************************************************/

static const int SIDs[8]={0xD400,0xD420,0xD500,0xD520,0xDE00,0xDE20,0xDF00,0xDF20};
#define SIDaddrtype unsigned char *
static SIDaddrtype SIDaddr;
static unsigned char SIDi;
static unsigned char version;
static unsigned char release;

typedef struct {
	const unsigned char left;
	const unsigned char top;
	const signed char rozsah;
} t_vyber_list;

typedef struct {
	unsigned char *vyber;
	const t_vyber_list *list;
	signed char *value;
} t_vyber;

static unsigned char vyber;
static unsigned char vyber_max;
signed char vyber_value[4];
const t_vyber_list extend_lists[4]={
	{0,4,7},
	{0,8,1},
	{0,12,3},
	{0,16,3}
};

//signed char audio_value[4];
#define audio_value	vyber_value
const t_vyber_list audio_lists[3]={
	{0,9,0},
	{0,14,4}
};

static unsigned char mem_value[8];

static signed char audio_mem[4];
static unsigned char isext;

static unsigned char isARM2;
static unsigned char mem_emul;
static unsigned char ntsc;
static unsigned char downM;
static unsigned char socket;

#define EMUL_SID		0
#define EMUL_SFX		1
#define EMUL_SFX_SID	2

#define ADDR_MAP_NONE		0
#define ADDR_MAP_SIDL		1
#define ADDR_MAP_SIDR		2
#define ADDR_MAP_SFX		3
#define ADDR_MAP_SIDM		4

#define ADDR_MAP_D400		0
#define ADDR_MAP_D420		1
#define ADDR_MAP_D500		2
#define ADDR_MAP_D520		3
#define ADDR_MAP_DE00		4
#define ADDR_MAP_DE20		5
#define ADDR_MAP_DF00		6
#define ADDR_MAP_DF20		7

#define EXTIN_NO			0
#define EXTIN_YES			0x65

#define DIGIFIX_NO		0
#define DIGIFIX_YES		0x58

void textcolorLB(void) {
	textcolor(COLOR_LIGHTBLUE);
}

void textcolorW(void) {
	textcolor(COLOR_WHITE);
}

//print char as a decimal
void cputbval(unsigned char x) {
	char sto=0;
	char deset=0;
	if (x>=100) {
		do {
			x-=100;sto++;
		} while (x>=100);
		cputc(sto+'0');
	}
	while (x>=10) {
		x-=10;deset++;
	}
	if (sto|deset) cputc(deset+'0');
	cputc(x+'0');
}

//print short as a 1/1000 decimal
void cput1000(unsigned short x) {
	char t=0;
	char m;
	while (x>=1000) {
		x-=1000;t++;
	}
	cputbval(t);
	cputc('.');
	t='0';while (x>=100) { x-=100;t++; } cputc(t);
	m=x;
	t='0';while (m>=10) { m-=10;t++; } cputc(t);
	cputc(m+'0');
}

//drawing acceleration, x,y = position, znak=character, kolik=number of characters, if negative then characters are in a column
typedef struct {
	unsigned char x;
	unsigned char y;
	unsigned char znak;
	signed char kolik;
} t_canvas;

//frame clearing
static const t_canvas prazdny_ramecek[]={
	{0,0,' ',40},
	{0,1,' ',-3},
	{39,1,' ',-3},
	{0,4,' ',40},
	{0,0,0,0}
};

//frame
static const t_canvas plny_ramecek[]={
	{0,0,'°',1},
	{1,0,'C',38},
	{39,0,'®',1},
	{0,1,'B',-3},
	{39,1,'B',-3},
	{0,4,'­',1},
	{1,4,'C',38},
	{39,4,0xBD,1},
	{0,0,0,0}
};

//one line
static const t_canvas lajna[]={
	{2,2,0xA3,36},
	{0,0,0,0}
};

//automaton for drawing acceleration structures, x0,y0 = position offset
void namaluj(unsigned char x0, unsigned char y0, const t_canvas *c) {
	while (c->znak) {
		signed char i=c->kolik;
		if (i<0) {
			while (++i<=0) {
				gotoxy(x0+c->x,y0+c->y-i);
				cputc(c->znak);
			}
		} else {
			gotoxy(x0+c->x,y0+c->y);
			while (i) { cputc(c->znak);i--; }
		}
		c++;
	}
}

//delay in miliseconds (approx.)
void delay(int ms) {
    volatile int t,t1;
    for(t=0;t<ms;t++) {
    	for(t1=0;t1<10;t1++);
    }
}

char get_p(void) {
	return SIDaddr[27];
}

char get_q(void) {
	return SIDaddr[28];
}

//sending command
void send_cmd(char x31, char x30) {
	SIDaddr[31]=x31;
	SIDaddr[30]=x30;
}

//plus wait 10ms
void send_cmd_wait(char x31, char x30) {
	send_cmd(x31,x30);
	delay(10);
}

//sending config command and reading half of the two-byte output
char get_pcmd(char x31, char x30) {
	send_cmd(x31,x30);
	delay(1);
	return get_p();
}

//close the config mode
void sid_off(void) {
	SIDaddr[29]=0;
	SIDaddr[29]=0;
	SIDaddr[29]=0;
}

//open the config mode
void sidoffon(void) {
	sid_off();
	delay(10);
	send_cmd('d','i');
	SIDaddr[29]='s';
	delay(1);
}

//print inverse character
void cputc_revers(char ch) {
        revers(1);
        cputc(ch);
        revers(0);
}

//new cputs with macros for color change and inversion text
void cputs2(const char *s) {
	while (*s) {
		if (*s=='L') {
			textcolor(COLOR_LIGHTBLUE);
		} else if (*s=='W') {
			textcolor(COLOR_WHITE);
/*		} else if (*s=='S') {
			revers(1);*/
		} else if (*s=='R') {
			revers(0);
		} else if (*s=='@') {
			s++;
			if (*s)	cputc_revers(*s);
			else break;
		} else if (*s=='\\') {
//			cputs("\r\n");
			cputc('\r');
			cputc('\n');
		} else {
			cputc(*s);
		}
		s++;
	}
}

//new cputsxy without cputs
void cputs2xy(const unsigned char x, const unsigned char y, const char *s) {
	gotoxy(x,y);
	cputs2(s);
}

void candidate() {
	if (release) {
		char x=wherex();
		char y=wherey();
    (void) bordercolor(COLOR_YELLOW);
    (void) textcolor(COLOR_YELLOW);
		revers(1);
		if (release==255) {
			cputs2xy(0,0,WarnBL);
			cputs2xy(0,24,WarnBL);
		} else {
			cputs2xy(0,0,WarnBeta);
			cputs2xy(0,24,WarnBeta);
		}
		revers(0);
		//back
    (void) textcolor(COLOR_WHITE);
		gotoxy(x,y);
	}
}

void new_page(void) {
    clrscr();
		candidate();
    cputs2((char *)Nadpis);
}

//print the first page header
void uvod(void) {
    (void) textcolor(COLOR_WHITE);
    (void) bordercolor(COLOR_LIGHTBLUE);
    (void) bgcolor(COLOR_BLUE);
    new_page();
}

//filter setting key reaction
signed char vyber_zmena(const t_vyber_list *v, char key, char ramecek) {
	signed char res=-1;
    if ((key==17)||(key==17+128)) {
		namaluj(v[vyber].left,v[vyber].top,/*(vyber==4)?prazdny_ramecek2:*/prazdny_ramecek);
    }
    switch (key) {
	case 17:
		//down
		vyber++;if (vyber>=vyber_max/*+isext*/) vyber=0;
		break;
	case 17+128:
		//up
		if (vyber>0) vyber--;
		else vyber=vyber_max-1/*+isext*/;
		break;
	case 29:
		//right
		if (v[vyber].rozsah) { if (vyber_value[vyber]<v[vyber].rozsah) { vyber_value[vyber]++;res=vyber; }
		} else { vyber_value[vyber]=1; res=vyber; }
		break;
	case 29+128:
		//left
		if (v[vyber].rozsah) { if (vyber_value[vyber]>-v[vyber].rozsah) { vyber_value[vyber]--;res=vyber; }
		} else { vyber_value[vyber]=0;res=vyber; }
		break;
	default:
	break;
    }
    if ((v[vyber].rozsah)&&((vyber_value[vyber]>v[vyber].rozsah)||(vyber_value[vyber]<-v[vyber].rozsah))) { vyber_value[vyber]=0;res=vyber; }
    if (((key==17)||(key==17+128))&&(ramecek)) {
		namaluj(v[vyber].left,v[vyber].top,/*(vyber==4)?plny_ramecek2:*/plny_ramecek);
    }
	namaluj(v[vyber].left,v[vyber].top,lajna);
	if (v[vyber].rozsah) {
    	gotoxy(v[vyber].left+19+((17*vyber_value[vyber])/v[vyber].rozsah),v[vyber].top+2);
	} else {
		gotoxy(v[vyber].left+2+34*(vyber_value[vyber]&1),v[vyber].top+2);
	}
    cputs2("\x7F\xA9");
	return res;
}

//print extended page offer
void save_back_quit(void) {
    gotoxy(4,23);
	cputs2("@save / @permanently / @back / @quit");
}

//print the filter setting page
void uvod_extend(void) {
    uvod();

    cputs2xy(/*extend_lists[0].left*/0+8,/*extend_lists[0].top*/4+1,       "mos 6581 filter strength");
    cputs2xy(/*extend_lists[0].left*/0+1,/*extend_lists[0].top*/4+3,"follin galway  average  strong exterme");

    cputs2xy(/*extend_lists[1].left*/0+4,/*extend_lists[1].top*/8+1,   "mos 6581 lowest filter frequency");
    cputs2xy(/*extend_lists[1].left*/0+1,/*extend_lists[1].top*/8+3," 150             215              310");

    cputs2xy(/*extend_lists[2].left*/0+4,/*extend_lists[2].top*/12+1,   "mos 8580 filter central frequency");
    cputs2xy(/*extend_lists[2].left*/0+1,/*extend_lists[2].top*/12+3," 12000           6000            3000");

    cputs2xy(/*extend_lists[3].left*/0+4,/*extend_lists[3].top*/16+1,   "mos 8580 lowest filter frequency");
    cputs2xy(/*extend_lists[3].left*/0+1,/*extend_lists[3].top*/16+3," 30              100              330");

	save_back_quit();

    vyber=0;
    vyber_zmena(extend_lists,17,0);
    vyber_zmena(extend_lists,17,0);
    vyber_zmena(extend_lists,17,0);
    vyber_zmena(extend_lists,17,1);
}

//print nibble as a hex value
void cputnibble(unsigned char x) {
	x&=15;
	if(x>9) x=('a'-10)+x;
	else x+='0';
	cputc(x);
}

//print short as a hex value
void cputhex(unsigned short x) {
	cputc('$');
	cputnibble(x>>12);
	cputnibble(x>>8);
	cputnibble(x>>4);
	cputnibble(x);
}

//saving configuration to the ram or permanently to the flash memory of ARMSID
void save(char jak) {
    char i;
    clrscr();
    uvod();
    switch(jak) {
	case 's':
	    gotoxy(13,12);
	    cputs2("saving to ram");
		send_cmd(0xC0,'e');
	    gotoxy(13,13);
	    for(i=0;i<13;i++) {
		delay(1000/13);
		cputc('#');
	    }
	break;
	case 'p':
	    gotoxy(12,12);
	    cputs2("saving to flash");
		send_cmd(0xCF,'e');
	    gotoxy(12,13);
	    for(i=0;i<15;i++) {
		delay(2000/15);
		cputc('#');
	    }
	break;
	default:break;
    }
}

//update memory mapping page with item x highlighted
void vyber_mem(char x) {
	char i;
	char is3=((mem_value[1]==ADDR_MAP_SIDM)||(mem_value[2]==ADDR_MAP_SIDM))&&(!socket);
	for(i=0;i<8;i++) {
	    gotoxy(5+((i>>2)?18:0),8+((i&3)<<1));
	    if (socket) {
			if (i&3) textcolor(COLOR_BLUE);
			if (i&4) cputs2("sid/2:");
			else cputs2("sid/1:");
			textcolorW();
		} else {
			cputhex(SIDs[i]);
			cputc(':');
		}
	}
	for(i=0;i<8;i++) {
	    gotoxy(5+7+((i>>2)?18:0),8+((i&3)<<1));
	    if (x==i) revers(1);
	    if (socket) {
			if (i&3) {
				textcolor(COLOR_BLUE);
				cputs2("none");
				goto vyber_dalsi;
			}
		}
		if ((mem_emul==EMUL_SFX_SID)&&(i<(socket?4:6))) {
			if (i==0) {
				cputs2("sidl");
			} else {
				cputs2("Lnone");
			}
		} else if ((i>=(socket?4:6))&&(mem_emul>=EMUL_SFX)) cputs2("sfx ");
	    else switch (mem_value[i]) {
			case ADDR_MAP_SFX:
				if (mem_emul==EMUL_SFX) textcolorLB();
				cputs2("sfx ");
				break;
			case ADDR_MAP_SIDL:
				if (mem_emul==EMUL_SFX) textcolorLB();
				cputs2("sidl");
				break;
			case ADDR_MAP_SIDR:
				if (mem_emul==EMUL_SFX) textcolorLB();
				if ((mem_emul==EMUL_SID)||(i>0)) cputs2("sidr");
				else cputs2("sidl");
				break;
			case ADDR_MAP_SIDM:
				if (mem_emul==EMUL_SFX) textcolorLB();
				else if (mem_emul==EMUL_SID) textcolor(COLOR_LIGHTGREEN);
				if ((mem_emul==EMUL_SID)||(i>0)) cputs2("sid3");
				else cputs2("sidl");
				break;
			case ADDR_MAP_NONE:
			default:
    			if (x!=i) textcolorLB();
				cputs2("none");
				break;
		}
vyber_dalsi:
		textcolorW();
	    if (x==i) revers(0);
	}
    gotoxy(4+18,16);
	if (!is3) cputc(' ');
	textcolorLB();
	if (mem_emul==EMUL_SFX_SID) {
		if (is3) { cputc(' '); }
		cputs2("sid sfx ");
		if (x==8) revers(1);
		cputs2("WbothR");
	} else if (mem_emul==EMUL_SFX) {
		if (is3) { cputc(' '); }
		cputs2("sid ");
		if (x==8) revers(1);
		cputs2("WsfxR LbothW");
	} else {
		if (x==8) revers(1);
		if (is3) { textcolor(COLOR_LIGHTGREEN);cputc('3'); }
		cputs2("WsidR Lsfx bothW");
	}
	//pal ntsc
	gotoxy(5+18,18);
	if (mem_emul==EMUL_SID) {
		cputs2("Lpal ntscW");
	} else {
		if (ntsc) {
			cputs2("Lpal W");
			if (x==9) revers(1);
			cputs2("ntscR");
		} else {
			if (x==9) revers(1);
			cputs2("palRL ntscW");
		}
	}
	//mono
	gotoxy(5+18,20);
	if (mem_emul==EMUL_SFX) {
		cputs2("Loff onW");
	} else {
		if (downM) {
			cputs2("Loff W");
			if (x==10) revers(1);
			cputs2("onR");
		} else {
			if (x==10) revers(1);
			cputs2("offRL onW");
		}
	}
	//socket
	gotoxy(5+18,6);
		if (socket) {
			cputs2("Lwire W");
			if (x==11) revers(1);
			cputs2("socketR");
		} else {
			if (x==11) revers(1);
			cputs2("wireRL socketW");
		}
}

static const char socket_next[12]={0,4,2,0,4,8,6,4,8,9,10,11};

//memory mapping key reaction
void mem_zmena(char key) {
	char vyber_old=vyber;
    switch (key) {
	case 17:
		//down
		vyber++;if (vyber>11) vyber=0;
		if ((vyber==9)&&(mem_emul==0)) vyber=10;
		if ((vyber==10)&&(mem_emul==1)) vyber=11;
		if ((mem_emul>=EMUL_SFX)&&(vyber<8)) vyber=8;
		break;
	case 17+128:
		//up
		if (vyber>0) vyber--;
		else vyber=11;
		if ((mem_emul>=EMUL_SFX)&&(vyber<8)) vyber=11;
		if ((vyber==10)&&(mem_emul==1)) vyber=9;
		if ((vyber==9)&&(mem_emul==0)) vyber=8;
		break;
	case 29:
		//right
		if (vyber==11) {
			socket^=1;
		} else if (vyber==10) {
			downM^=1;
		} else if (vyber==9) {
			ntsc^=4;
		} else if (vyber==8) {
			mem_emul++;//=(mem_emul+1)%3;
			if (mem_emul>=3) mem_emul=0;
		} else {
			mem_value[vyber]++;
			if (mem_value[vyber]>4) mem_value[vyber]=0;
			else if (mem_value[vyber]>2) {
				if (vyber==0) mem_value[vyber]=1;
				else {
					if ((vyber==1)||(vyber==2)) mem_value[vyber]=4;	//enable for D420 a D500
					else mem_value[vyber]=0;
				}
			}
		}
		break;
	case 29+128:
		//left
		if (vyber==11) {
			socket^=1;
		} else if (vyber==10) {
			downM^=1;
		} else if (vyber==9) {
			ntsc^=4;
		} else if (vyber==8) {
			mem_emul+=2;
			if (mem_emul>=3) mem_emul-=3;
		}
		else {
			if (mem_value[vyber]==0) {
				if ((vyber==0)||(vyber>2)) mem_value[vyber]=2;	//povolit jen pro D420 a D500
				else mem_value[vyber]=4;
			}
			else if (mem_value[vyber]==4) mem_value[vyber]=2;
			else mem_value[vyber]--;
			if ((vyber==0)&&(mem_value[vyber]==0)) mem_value[vyber]=2;
		}
		break;
	default:
	break;
    }
    if (vyber_old!=vyber) {
		vyber_mem(-1);
		if (socket) vyber=socket_next[vyber];
	}
    vyber_mem(vyber);
}

//print memory mapping page
void uvod_mem(void) {
    uvod();
    gotoxy(5,3);
    cputs2("address mapping configuration");
    gotoxy(5,6);
    cputs2("pin connections:");
    gotoxy(5,16);
    cputs2("emulation mode: ");
    gotoxy(5,18);
    cputs2("fm frequency ref:");
    gotoxy(5,20);
    cputs2("down-mix to mono:");
	save_back_quit();
	vyber=8;
	vyber_mem(vyber);
}

//memory mapping reading
void nacti_mem(void) {
    unsigned char p,q;
	p=get_pcmd('m','m');
    q=get_q();
    mem_emul=p&7;
    if (mem_emul&4) ntsc=4; else ntsc=0;
    if ((mem_emul&3)==3) mem_emul=1;
    mem_emul&=3;
	p=get_pcmd('x','m');
    q=get_q();
    downM=p&1;
    socket=q&1;
    delay(10);
	p=get_pcmd('l','m');
    q=get_q();
    mem_value[0]=p&15;
    mem_value[1]=p>>4;
    mem_value[2]=q&15;
    mem_value[3]=q>>4;
    delay(10);
	p=get_pcmd('h','m');
    q=get_q();
    mem_value[4]=p&15;
    mem_value[5]=p>>4;
    mem_value[6]=q&15;
    mem_value[7]=q>>4;
}

//memory mapping page automaton
char mem(void) {
    char key;
    uvod_mem();
    while (1) {
    	if (kbhit()) {
			key=cgetc();
			if ((key=='q')||(key=='b')) return key;
			if ((key=='s')||(key=='p')) {
				send_cmd_wait('0'+(mem_emul)+((mem_emul)?(ntsc):0),'m');
				send_cmd_wait(((downM)?'r':'s'),'m');
				send_cmd_wait(((socket)?'e':'c'),'m');
				{
					unsigned char i=0;
					while (i<8) {
						send_cmd_wait(0x80|(i<<4)|(mem_value[i]&15),'m');
						i++;
					}
				}
			}
			if (key=='s') {
			save(key);
			return 'r';
			}
			if (key=='p') {
			save(key);
			return 'r';
			}
		    mem_zmena(key);
		}
    }
}

//ARM2SID testing => if answer to command "SII" is L or R then it's ARM2SID otherwise it's ARMSID
char test_lr(char x) {
	unsigned char p,q;
	char res=0;
	isARM2=0;
	SIDaddr=(SIDaddrtype)(SIDs[x]);SIDi=x;
	sidoffon();
	p=get_pcmd('i','i');
	q=get_q();
	if (p!=2) res=0;		//neni ARM2
	else if (q==CHAR_L) { res=1;isARM2=1; }	//je levy kanal
	else if (q==CHAR_R) { res=2;isARM2=1; }	//je pravy kanal
	sid_off();
	return res;
}

void printf_sid(char sid, int addr) {
	cputs2(Founda[test_lr(sid)]);cputs2(" found at ");cputhex(addr);cputs2("\\");
}

void printf_sidi(void) {
	printf_sid(SIDi,(int)SIDaddr);
}

void printf_found(char n, char sid) {
	cputc(n+'0');cputs2(") ");printf_sid(sid,(int)SIDs[sid]);
}

signed char vyber_sid(char i) {
    signed char res=0;
    char id[3];
    char n=0;
    char a;
    cputs2("more than one armsid found !\\\\");
    if (i&1) {
	id[n++]=1;
	printf_found(n,0);
    }
    if (i&2) {
	id[n++]=2;
	printf_found(n,1);
    }
    if (i&4) {
	id[n++]=3;
	printf_found(n,2);
    }
    cputs2("\\press ");
    if (n==3) {
		cputs2("@1,@2 or @3");
    } else {
		cputs2("@1 or @2");
    }
    cputs2(" to choose one\\or press @q to quit\\");
	while (1) {
	    if (kbhit()) {
		a=cgetc();
		if (a=='q') { res=-1; break; }
		if ((a>='0')&&(a<='9')) {
		    a=a-'1';
		    if (a<n) {
			res=id[a];
			SIDaddr=(SIDaddrtype)(SIDs[res-1]);SIDi=res-1;
		    }
		    break;
		}
	    }
	}
    return res;
}

void najdi2(void) {
	printf_sidi();
	sidoffon();
}

//ARMSID search
signed char najdi(void) {
    unsigned char i,p,q,maska;
    char j;
    maska=0;j=1;
    for(i=0;i<3;i++,j<<=1) {
		SIDaddr=(SIDaddrtype)(SIDs[i]);SIDi=i;
		SIDaddr[24]=0;	//silent
		SIDaddr[24]=0;
		SIDaddr[24]=0;
		sidoffon();
		p=get_p();
		q=get_q();
		if ((p!=CHAR_N)||(q!=CHAR_O)) {
		    continue;
		}
		p=get_pcmd('e','i');
		q=get_q();
		if ((p!=CHAR_S)||(q!=CHAR_W)) {
		    continue;
		}
		maska|=j;
    }
    i=0;
    switch (maska) {
	case 1:	i=1;
		SIDaddr=(SIDaddrtype)(SIDs[0]);SIDi=0;
		break;
	case 2:	i=2;
		SIDaddr=(SIDaddrtype)(SIDs[1]);SIDi=1;
		break;
	case 3:	SIDaddr=(SIDaddrtype)(SIDs[1]);SIDi=1;
		sidoffon();
		SIDaddr=(SIDaddrtype)(SIDs[0]);SIDi=0;
		p=get_p();
		q=get_q();
		if ((p!=CHAR_S)||(q!=CHAR_W)) {
		    i=1;
		    break;
		}
		i=vyber_sid(3);
		break;
	case 4:	i=3;
		SIDaddr=(SIDaddrtype)(SIDs[2]);SIDi=2;
		break;
	case 5:	SIDaddr=(SIDaddrtype)(SIDs[2]);SIDi=2;
		sidoffon();
		SIDaddr=(SIDaddrtype)(SIDs[0]);SIDi=0;
		p=get_p();
		q=get_q();
		if ((p!=CHAR_S)||(q!=CHAR_W)) {
		    i=1;
		    break;
		}
		i=vyber_sid(5);
		break;
	case 6:	SIDaddr=(SIDaddrtype)(SIDs[2]);SIDi=2;
		sidoffon();
		SIDaddr=(SIDaddrtype)(SIDs[1]);SIDi=1;
		p=get_p();
		q=get_q();
		if ((p!=CHAR_S)||(q!=CHAR_W)) {
		    i=2;
		    break;
		}
		i=vyber_sid(6);
		break;
	case 7:	SIDaddr=(SIDaddrtype)(SIDs[0]);SIDi=0;
		sidoffon();
		SIDaddr=(SIDaddrtype)(SIDs[1]);SIDi=1;
		p=get_p();
		q=get_q();
		if ((p!=CHAR_S)||(q!=CHAR_W)) {
		    SIDaddr=(SIDaddrtype)(SIDs[2]);SIDi=2;
		    p=get_p();
		    q=get_q();
		    if ((p!=CHAR_S)||(q!=CHAR_W)) {	//vypadava 1 a 2
		    	SIDaddr=(SIDaddrtype)(SIDs[0]);SIDi=0;
			i=1;
			break;
		    } else {	//vypadava 1
			i=vyber_sid(5);
		    }
		} else {
		    SIDaddr=(SIDaddrtype)(SIDs[2]);SIDi=2;
		    p=get_p();
		    q=get_q();
		    if ((p!=CHAR_S)||(q!=CHAR_W)) {	//vypadava 2
			i=vyber_sid(3);
		    } else {	//zustava 0,1 a 2
			SIDaddr=(SIDaddrtype)(SIDs[2]);SIDi=2;
			sidoffon();
			SIDaddr=(SIDaddrtype)(SIDs[1]);SIDi=1;
			p=get_p();
			q=get_q();
			if ((p!=CHAR_S)||(q!=CHAR_W)) {
			    i=vyber_sid(3);
			} else {
			    i=vyber_sid(7);
			}
		    }
		}
		break;
	default:i=0;
		break;
    }
    if (i>0) {
		printf_sidi();
    } else {
		cputs2(Notfou);
		cputs2("\\");
    }
    return i;
}

void cputascii(unsigned char c) {
	if ((c<=0x20)||(c>=128)) c='/';
	cputc(c);
}

//details printing
void details(void) {
  unsigned char p,q;
	p=get_pcmd('v','i');
    q=get_q();
    version=p;
    cputs2("fw version:");
    cputbval(p);
    cputc('.');
    cputbval(q);
		p=get_pcmd('r','i');
		if ((p>'0')&&(p<CHAR_E)) {
			release=p-'0';
			cputs2(" beta ");
			cputbval(release);
		}
		cputs2("\\");

	p=get_pcmd('f','i');
    if ((p<=32)||(p>127)) p='.';
    q=get_q();if ((q<=32)||(q>127)) q='.';
    if (version>=2) {
	cputs2("emulated device:");
    cputc(p);
    cputc(q);
	cputs2("xx");
	p=get_pcmd('g','i');
	if (p=='7') cputs2("(auto detected)\\");
	else cputs2("               \\");
    } else {
	cputs2("emulated device:");
    cputc(p);
    cputc(q);
	cputs2("xx\\");
    }
	p=get_pcmd('i','f');
    if ((p<=32)||(p>127)) p='.';
    q=get_q();if ((q<=32)||(q>127)) q='.';
    cputs2("app/boot:");
    cputc(p);
    cputc(q);
		if ((p==CHAR_B)&&(q==CHAR_L)) release=255;
	cputs2("\\");
	p=get_pcmd(0xC0,'i');q=get_q();
	if ((p==0x55) && (q==0x49))	{	// UI
		unsigned char ii;
    cputs2("s/n:");
		p=get_pcmd(0xC3,'i');
		q=get_q();
		cputascii(q);
		for (ii=0xC4;ii<=0xC6;ii++) {
			p=get_pcmd(ii,'i');
			q=get_q();
			cputascii(p);
			cputascii(q);
		}
		cputc('/');
		p=get_pcmd(0xC3,'i');
		cputbval(p);
		cputc('/');
		p=get_pcmd(0xC1,'i');
		q=get_q();
		if (q>0) cputascii(q+0x40);
		cputbval(p);
		cputc('/');
		p=get_pcmd(0xC2,'i');
		q=get_q();
		if (q>0) cputascii(q+0x40);
		cputbval(p);
	}
    isext=0;
	p=get_pcmd(0x64,'i');
   	q=get_q();
    if ((p==0x64)&&((q==DIGIFIX_NO)||(q==DIGIFIX_YES))) isext=1;
    cputs2("\\\\\\\\\\\\press ");
	cputs2("@6/@7/@8 to 6581/auto/8580 emulation\\press ");
    if (version>=2) {
		cputs2("@p to permanently save\\press @e to extended (filter) menu ...\\press ");
    }
	if (isext) {
		cputs2("@d to mos8580 digifix settings ...\\press ");
	}
	if (isARM2) {
		cputs2("@m to address mapping configurationpress ");
	}
	cputs2("@r to restart the tester\\and @q to quit\\");
    if (version>=2) {
    } else {
    	cputs2("  upgrade firmware to version 2.0 and\\      newer for new features !!!\\");
    }
    gotoy(11);
		if (release) candidate();
}

void fillx(unsigned char x)
{
	signed char n=x-wherex();
	while(n-->0) cputc(' ');
}

//analog values test
void analog(void) {
    unsigned char x,y,mem;
    short v;
    mem=wherey();
    x=SIDaddr[25];
    y=SIDaddr[26];
    cputs2("potx=");
    cputbval(x);fillx(15);
    cputs2("\\poty=");
    cputbval(y);fillx(15);
    ((char*)&v)[1]=get_pcmd('u','i');
    ((char*)&v)[0]=get_q();
    cputs2("\\vdd=");
    cput1000(v);
    cputs2(" v");fillx(15);
    ((char*)&v)[1]=get_pcmd('t'+0x20,'i');
    ((char*)&v)[0]=get_q();
    if (v!=0x4552) {
    	cputs2("Lt=");
    	if (v<0) {
			cputc('-');
			v=0-v;
		}
	    cputbval(v/10);
		cputc('.');
	    cputbval(v%10);
		cputs2("\274cW     ");
	}
    gotoxy(0,mem);
}

//filter setting reading
void nacti_extend(void) {
    unsigned char p,q;
    signed char v;
    vyber_max=4;
	p=get_pcmd('h','i');
    q=get_q();
    v=p;
    v=v>>4;
    vyber_value[0]=v;
    v=p<<4;
    v=v>>4;
    vyber_value[1]=v;
    v=q;
    v=v>>4;
    vyber_value[2]=v;
    v=q<<4;
    v=v>>4;
    vyber_value[3]=v;
}

//extended page (filter setting) automaton
char extended(void) {
    char key;
    uvod_extend();
    while (1) {
    	if (kbhit()) {
				key=cgetc();
				if ((key=='q')||(key=='b')) return key;
				if ((key=='s')||(key=='p')) {
					unsigned char i=0;
					while (i<4) {
						send_cmd_wait(0x80|(i<<4)|(vyber_value[i]&15),'e');
						i++;
					}
					save(key);
					return 0;
				}
				vyber_zmena(extend_lists,key,1);
			}
    }
}

void ping(unsigned char st) {
static SIDaddrtype ping_sid;
	unsigned char n;
	unsigned char d;
	unsigned char x=0;
	if (audio_mem[2]==0) return;
	send_cmd_wait(st,'e');
	sid_off();
	SIDaddr[23]=7;
	ping_sid=&SIDaddr[24];
	*ping_sid=0;
	delay(70);
	d=15;
	while(d) {
		unsigned char up=1;
		n=100;
		while (n) {
			if (up&&(x<d)) ++x; else up=0;
			if (!up&&x) --x; else up=1;
			*ping_sid=x;
			--n;
		}
		--d;
	}
	*ping_sid=0;
	sidoffon();
	send_cmd_wait(audio_mem[2],'e');
}

void digifix_analog(void) {
    short v,vv;
    short vref;
    gotoxy(2,5);
    ((char*)&vref)[1]=get_pcmd('r'^0x20,'i');
    ((char*)&vref)[0]=get_q();
	if (isARM2) {
	    if (vref!=0x4552) {
	    	cputs2("Lref=");
		    cput1000(vref);
		    cputs2(" vW");
		} else vref=3300;
	    fillx(16);
	}
    ((char*)&v)[1]=get_pcmd('e'^0x20,'i');
    ((char*)&v)[0]=get_q();
    if (v!=0x4552) {
			vv=vref/2-v;
    	cputs2("\\  vin=");
    	if (v<0) {
			cputc('-');
			v=0-v;
		}
	    cput1000(v);
	    cputs2(" v    \\  iin=");
	    v+=v;
	    v=v-vref;
	    v*=5;
	    v/=4;	//*0.8
	    v=v+v/128;
    	if (v<0) {
			cputc('-');
			v=0-v;
		} else cputc('+');
		cputbval(v/100);
		v%=100;
		cputc('.');
	    cputbval(v/10);
	    cputbval(v%10);
		cputs2(" ua");
	    fillx(16);
		gotoxy(32,14+6);
		vv*=12;
		vv/=41;
		if (vv>100) vv=100;
		if (vv<-100) vv=-100;
   	if (vv<0) {
		cputc('-');
		vv=0-vv;
		}
		cputbval(vv);
		cputc('%');
    fillx(39);
	}
}

void nacti_digifix(void) {
    unsigned char p,q;
    signed char s;
    vyber_max=2;

	// audio in
	p=get_pcmd(0x64,'i');
   	q=get_q();
   	audio_value[0]=0;
    if ((p==0x64)&&(q==DIGIFIX_YES)) audio_value[0]=1;
    audio_mem[0]=audio_value[0];

	p=get_pcmd('8','i');
   	s=get_q()-128;
   	audio_value[2]=4;
   	s=s/8;
    if ((p=='d')&&(s>=-4)&&(s<=4)) audio_value[1]=s;
    audio_mem[1]=audio_value[1];

	// SID type
	p=get_pcmd('g','i');
   	s=get_q();
    if ((s=='5')&&(p>='6')&&(p<='8')) audio_mem[2]=p;
    else audio_mem[2]=0;
}

void lineupdate_digifix(void) {
	if (audio_value[0]) {
		textcolorW();
	} else {
		textcolorLB();
	}
    cputs2xy(3,14+1,  "mos 8580 software digifix strength");
    cputs2xy(1,14+3,"-100 -75 -50 -25  0%  25  50  75  100");
	if (audio_value[0]) {
		textcolorLB();
	} else {
		textcolorW();
	}
		cputs2xy(2,14+6,"digifix by ext. hardware pin: ");
	textcolorW();
}

void uvod_digifix(void) {
    uvod();
    cputs2xy( 8,3,     "digifix mos8580 settings");
    cputs2xy(9, 9+1,        "digifix controlled by");
    cputs2xy(1 ,9+3," hardware                    software");
		lineupdate_digifix();

	save_back_quit();

    vyber=0;
	vyber_zmena(audio_lists,17,0);
	vyber_zmena(audio_lists,17,1);
}

//extended page (filter setting) automaton
char digifix(void) {
    char key,res;
    uvod_digifix();
    SIDaddr[4]=0;
    SIDaddr[11]=0;
    SIDaddr[18]=0;
    SIDaddr[23]=0;
    while (1) {

			vyber_max=audio_value[0]+1;

    	if (kbhit()) {
			key=cgetc();
			SIDaddr[24]=0;
			if ((key=='q')||(key=='b')) {
				send_cmd_wait((audio_mem[0])?0x64:0x44,'a');
				send_cmd_wait((audio_mem[1]&0x0F)|0xB0,'a');
				return key;
			}
			if ((key=='s')||(key=='p')) {
				send_cmd_wait((audio_value[0])?0x64:0x44,'a');
				send_cmd_wait((audio_value[1]&0x0F)|0xB0,'a');
				save(key);
				return 0;
			}
			res=vyber_zmena(audio_lists,key,1);
			switch (res) {
				case 0:
					send_cmd_wait((audio_value[0])?0x64:0x44,'a');
					lineupdate_digifix();
				    break;
				case 1:
					send_cmd_wait(0x64,'a');
					send_cmd_wait((audio_value[1]&0x0F)|0xB0,'a');
					ping('8');
				    break;
				default:
				    break;
			}
		} else {
			digifix_analog();
			delay(150);
		}
    }
}

////////////////////////////////////////////////////////////////////////////////

int main (void)
{
    signed char a=0;
    *(unsigned char *)0xd018 = 0x15;	//just uppercase letters
    while (a!='q') {
	release=0;
	uvod();
	a=najdi();
	if (a<=0) break; //return EXIT_SUCCESS;
	while ((a!='q')&&(a!='r')) {
	    uvod();
	    najdi2();
	    details();
	    while (1) {
		analog();
		if (kbhit()) {
		    a=cgetc();
		    if ((a=='q')||(a=='r')) {
			clrscr();
			gotoxy(1,1);
			break;
		    }
		    if ((a>='6')&&(a<='8')) {
			send_cmd_wait(a,'e');
			break;
		    }
			if (isARM2) {
				if (a=='m') {	//mem map cfg
					nacti_mem();
					a=mem();
					if (a=='q') {
						clrscr();
						gotoxy(1,1);
						break;
					}
					break;
				}
			}
			if (isext) {
				if (a=='d') {	//digifix
					clrscr();
					nacti_digifix();
					a=digifix();
					if (a=='q') {
						clrscr();
						gotoxy(1,1);
						break;
					}
					break;
				}
			}
		    if (version>=2) {
				if (a=='p') {
					save('p');
					break;
				}
				if (a=='e') {
					nacti_extend();
					a=extended();
					if (a=='q') {
						clrscr();
						gotoxy(1,1);
						break;
					}
					a=0;
					break;
				}
		    }
		}
		delay(150);
	    }
	}
	cputs2("\\\\\\\\\\\\");
	sid_off();
    }
  (void) bordercolor(COLOR_LIGHTBLUE);
  return EXIT_SUCCESS;
}

