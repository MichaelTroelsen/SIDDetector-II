/*
** ArmSID & Arm2SID tester/configurator using cc65.
**
** Bohumil Novacek (dzin@post.cz)
**
*/

#include <stdlib.h>
#include <conio.h>

/*****************************************************************************/
/*                                   Data                                    */
/*****************************************************************************/

static const char Nadpis [] = "\r\n\r\n       nobomi armsid tester v3.2\r\n";
#define Nadpis_extend Nadpis
static const char Notfou [] = "armsid not found";
static const char Founda [3][34] = { "armsid" , "arm2sid  left channel" , "arm2sid right channel" };

/*****************************************************************************/
/*                                   Code                                    */
/*****************************************************************************/

static const int SIDs[8]={0xD400,0xD420,0xD500,0xD520,0xDE00,0xDE20,0xDF00,0xDF20};
static unsigned char *SIDaddr;
static unsigned char SIDi;
static unsigned char isARM2;
static unsigned char version;
static unsigned char vyber;
static const char vyber_left[4]={0,0,0,0};
static const char vyber_top[4]={4,8,12,16};
static const signed char vyber_rozsah[4]={7,1,3,3};
static signed char vyber_value[4];
static unsigned char mem_value[8];
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

void textcolorLB() {
	textcolor(COLOR_LIGHTBLUE);
}

void textcolorW() {
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
void namaluj(unsigned char x0, unsigned char y0, t_canvas *c) {
	while (c->znak) {
		signed char i=c->kolik;
		if (i<0) {
			while (++i<=0) {
				gotoxy(x0+c->x,y0+c->y-i);
				cputc(c->znak);
			}
		} else {
			gotoxy(x0+c->x,y0+c->y);
			while (i-->0) cputc(c->znak);
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

char get_p() {
	return SIDaddr[27];
}

char get_q() {
	return SIDaddr[28];
}

//sending config command and reading half of the two-byte output
char get_pcmd(char x31, char x30) {
	SIDaddr[31]=x31;
	SIDaddr[30]=x30;
	delay(1);
	return get_p();
}

//close the config mode
void sid_off() {
	SIDaddr[29]=0;
	SIDaddr[29]=0;
	SIDaddr[29]=0;
}

//open the config mode
void sidoffon() {
	sid_off();
	delay(10);
	SIDaddr[31]='d';
	SIDaddr[30]='i';
	SIDaddr[29]='s';
	delay(1);
}

//print the first page header
void uvod() {
    (void) textcolor (COLOR_WHITE);
    (void) bordercolor (COLOR_LIGHTBLUE);
    (void) bgcolor (COLOR_BLUE);
    clrscr();
    cputs (Nadpis);
    cputs ("\r\n\r\n");
}

//print inverse character
void cputc_revers(char ch) {
        revers(1);
        cputc(ch);
        revers(0);
}

//new cputs with macros for color change and inversion text
void cputs2(char *s) {
	while (*s) {
		if (*s=='L') {
			textcolor(COLOR_LIGHTBLUE);
		} else if (*s=='W') {
			textcolor(COLOR_WHITE);
		} else if (*s=='R') {
			revers(0);
		} else if (*s=='@') {
			s++;
			if (*s)	cputc_revers(*s);
			else break;
		} else {
			cputc(*s);
		}
		s++;
	}
}

//filter setting key reaction
void vyber_zmena(char key, char ramecek) {
    if ((key==17)||(key==17+128)) {
		namaluj(vyber_left[vyber],vyber_top[vyber],(t_canvas *)&prazdny_ramecek[0]);
    }
    switch (key) {
	case 17:
		//down
		vyber++;if (vyber>=4) vyber=0;
		break;
	case 17+128:
		//up
		if (vyber>0) vyber--;
		else vyber=4-1;
		break;
	case 29:
		//right
		if (vyber_value[vyber]<vyber_rozsah[vyber]) vyber_value[vyber]++;
		break;
	case 29+128:
		//left
		if (vyber_value[vyber]>-vyber_rozsah[vyber]) vyber_value[vyber]--;
		break;
	default:
	break;
    }
    if ((vyber_value[vyber]>vyber_rozsah[vyber])||(vyber_value[vyber]<-vyber_rozsah[vyber])) vyber_value[vyber]=0;
    if (((key==17)||(key==17+128))&&(ramecek)) {
		namaluj(vyber_left[vyber],vyber_top[vyber],(t_canvas *)&plny_ramecek[0]);
    }
	namaluj(vyber_left[vyber],vyber_top[vyber],(t_canvas *)&lajna[0]);
    gotoxy(vyber_left[vyber]+19+((17*vyber_value[vyber])/vyber_rozsah[vyber]),vyber_top[vyber]+2);
    cputs("\x7F\xA9");
}

//print extended page offer
void save_back_quit() {
    gotoxy(4,23);
	cputs2("@save / @permanently / @back / @quit");
}

//print the filter setting page
void uvod_extend() {
    (void) textcolor (COLOR_WHITE);
    (void) bordercolor (COLOR_LIGHTBLUE);
    (void) bgcolor (COLOR_BLUE);

    clrscr ();
    cputs(Nadpis_extend);
    cputs("\r\n\r\n");

    cputsxy(vyber_left[0]+8,vyber_top[0]+1,       "mos 6581 filter strength");
    cputsxy(vyber_left[0]+1,vyber_top[0]+3,"follin galway  average  strong exterme");

    cputsxy(vyber_left[1]+4,vyber_top[1]+1,   "mos 6581 lowest filter frequency");
    cputsxy(vyber_left[1]+1,vyber_top[1]+3," 150             215              310");

    cputsxy(vyber_left[2]+4,vyber_top[2]+1,   "mos 8580 filter central frequency");
    cputsxy(vyber_left[2]+1,vyber_top[2]+3," 12000           6000            3000");

    cputsxy(vyber_left[3]+4,vyber_top[3]+1,   "mos 8580 lowest filter frequency");
    cputsxy(vyber_left[3]+1,vyber_top[3]+3," 30              100              330");

	save_back_quit();

    vyber=0;
    vyber_zmena(17,0);
    vyber_zmena(17,0);
    vyber_zmena(17,0);
    vyber_zmena(17,1);
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

//update memory mapping page with item x highlighted
void vyber_mem(char x) {
	char i;
	char is3=((mem_value[1]==ADDR_MAP_SIDM)||(mem_value[2]==ADDR_MAP_SIDM))&&(!socket);
	for(i=0;i<8;i++) {
	    gotoxy(5+((i>>2)?18:0),8+((i&3)<<1));
	    if (socket) {
			if (i&3) textcolor(COLOR_BLUE);
			if (i&4) cputs("sid/2:");
			else cputs("sid/1:");
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
				cputs("none");
				goto vyber_dalsi;
			}
		}
		if ((mem_emul==EMUL_SFX_SID)&&(i<(socket?4:6))) {
			if (i==0) {
				cputs("sidl");
			} else {
				cputs2("Lnone");
			}
		} else if ((i>=(socket?4:6))&&(mem_emul>=EMUL_SFX)) cputs("sfx ");
	    else switch (mem_value[i]) {
			case ADDR_MAP_SFX:
				if (mem_emul==EMUL_SFX) textcolorLB();
				cputs("sfx ");
				break;
			case ADDR_MAP_SIDL:
				if (mem_emul==EMUL_SFX) textcolorLB();
				cputs("sidl");
				break;
			case ADDR_MAP_SIDR:
				if (mem_emul==EMUL_SFX) textcolorLB();
				if ((mem_emul==EMUL_SID)||(i>0)) cputs("sidr");
				else cputs("sidl");
				break;
			case ADDR_MAP_SIDM:
				if (mem_emul==EMUL_SFX) textcolorLB();
				else if (mem_emul==EMUL_SID) textcolor(COLOR_LIGHTGREEN);
				if ((mem_emul==EMUL_SID)||(i>0)) cputs("sid3");
				else cputs("sidl");
				break;
			case ADDR_MAP_NONE:
			default:
    			if (x!=i) textcolorLB();
				cputs("none");
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
		cputs("sid sfx ");
		if (x==8) revers(1);
		cputs2("WbothR");
	} else if (mem_emul==EMUL_SFX) {
		if (is3) { cputc(' '); }
		cputs("sid ");
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
		static const char socket_next[12]={0,4,2,0,4,8,6,4,8,9,10,11};
		vyber_mem(-1);
		if (socket) vyber=socket_next[vyber];
	}
    vyber_mem(vyber);
}

//print memory mapping page
void uvod_mem() {
    (void) textcolor (COLOR_WHITE);
    (void) bordercolor (COLOR_LIGHTBLUE);
    (void) bgcolor (COLOR_BLUE);
    clrscr ();
    cputs(Nadpis_extend);
    cputs("\r\n\r\n");
    gotoxy(5,3);
    cputs("address mapping configuration");
    gotoxy(5,6);
    cputs("pin connections:");
    gotoxy(5,16);
    cputs("emulation mode: ");
    gotoxy(5,18);
    cputs("fm frequency ref:");
    gotoxy(5,20);
    cputs("down-mix to mono:");
	save_back_quit();
	vyber=8;
	vyber_mem(vyber);
}

//ARM2SID testing => if answer to command "SII" is L or R then it's ARM2SID otherwise it's ARMSID
char test_lr(char x) {
#ifdef DEMO
	SIDaddr=(char *)(SIDs[x]);SIDi=x;
	isARM2=1;return (x+1)%3;
#else
	unsigned char p,q;
	char res=0;
	isARM2=0;
	SIDaddr=(char *)(SIDs[x]);SIDi=x;
	sidoffon();
	p=get_pcmd('i','i');
	q=get_q();
	if (p!=2) res=0;		//neni ARM2
	else if (q=='l') { res=1;isARM2=1; }	//je levy kanal
	else if (q=='r') { res=2;isARM2=1; }	//je pravy kanal
	sid_off();
	return res;
#endif
}

void printf_sid(char sid, int addr) {
	cputs(Founda[test_lr(sid)]);cputs(" found at ");cputhex(addr);cputs("\r\n");
}

void printf_sidi() {
	printf_sid(SIDi,(int)SIDaddr);
}

void printf_found(char n, char sid) {
	cputc(n+'0');cputs(") ");printf_sid(sid,(int)SIDs[sid]);
}

char vyber_sid(char i) {
    char res=0;
    char id[3];
    char n=0;
    char a;
    cputs("more than one armsid found !\r\n\r\n");
    if (i&1) {
	id[n++]=1;
	//cprintf ("%d%s%sd%X\r\n",n,") ", Founda[test_lr(0)],((int)SIDs[0])&0x0FFF);
	printf_found(n,0);
    }
    if (i&2) {
	id[n++]=2;
	//cprintf ("%d%s%sd%X\r\n",n,") ", Founda[test_lr(1)],((int)SIDs[1])&0x0FFF);
	printf_found(n,1);
    }
    if (i&4) {
	id[n++]=3;
	//cprintf ("%d%s%sd%X\r\n",n,") ", Founda[test_lr(2)],((int)SIDs[2])&0x0FFF);
	printf_found(n,2);
    }
    cputs ("\r\npress ");
    if (n==3) {
		cputs2("@1,@2 or @3");
    } else {
		cputs2("@1 or @2");
    }
    cputs2 (" to choose one\r\nor press @q to quit\r\n");
	while (1) {
	    if (kbhit()) {
		a=cgetc();
		if (a=='q') break;
		if ((a>='0')&&(a<='9')) {
		    a=a-'1';
		    if (a<n) {
			res=id[a];
			SIDaddr=(char *)(SIDs[res-1]);SIDi=res-1;
		    }
		    break;
		}
	    }
	}
    return res;
}

char najdi2() {
	printf_sidi();
	sidoffon();
    return 1;
}

#ifdef DEMO
char nexti=0;
#endif

//ARMSID search
char najdi() {
    char i,j;
    unsigned char p,q,maska;
    maska=0;j=1;
    for(i=0;i<3;i++,j<<=1) {
		SIDaddr=(char *)(SIDs[i]);SIDi=i;
		SIDaddr[24]=0;	//silent
		SIDaddr[24]=0;
		SIDaddr[24]=0;
		sidoffon();
		p=get_p();
		q=get_q();
		if ((p!='n')||(q!='o')) {
#ifndef DEMO
		    continue;
#endif
		}
		p=get_pcmd('e','i');
		q=get_q();
		if ((p!='s')||(q!='w')) {
#ifndef DEMO
		    continue;
#endif
		}
		maska|=j;
    }
    i=0;
    switch (maska) {
	case 1:	i=1;
		SIDaddr=(char *)(SIDs[0]);SIDi=0;
		break;
	case 2:	i=2;
		SIDaddr=(char *)(SIDs[1]);SIDi=1;
		break;
	case 3:	SIDaddr=(char *)(SIDs[1]);SIDi=1;
		sidoffon();
		SIDaddr=(char *)(SIDs[0]);SIDi=0;
		p=get_p();
		q=get_q();
		if ((p!='s')||(q!='w')) {
		    i=1;
		    break;
		}
		i=vyber_sid(3);
		break;
	case 4:	i=3;
		SIDaddr=(char *)(SIDs[2]);SIDi=2;
		break;
	case 5:	SIDaddr=(char *)(SIDs[2]);SIDi=2;
		sidoffon();
		SIDaddr=(char *)(SIDs[0]);SIDi=0;
		p=get_p();
		q=get_q();
		if ((p!='s')||(q!='w')) {
		    i=1;
		    break;
		}
		i=vyber_sid(5);
		break;
	case 6:	SIDaddr=(char *)(SIDs[2]);SIDi=2;
		sidoffon();
		SIDaddr=(char *)(SIDs[1]);SIDi=1;
		p=get_p();
		q=get_q();
		if ((p!='s')||(q!='w')) {
		    i=2;
		    break;
		}
		i=vyber_sid(6);
		break;
	case 7:	SIDaddr=(char *)(SIDs[0]);SIDi=0;
		sidoffon();
		SIDaddr=(char *)(SIDs[1]);SIDi=1;
		p=get_p();
		q=get_q();
		if ((p!='s')||(q!='w')) {
		    SIDaddr=(char *)(SIDs[2]);SIDi=2;
		    p=get_p();
		    q=get_q();
		    if ((p!='s')||(q!='w')) {	//vypadava 1 a 2
		    	SIDaddr=(char *)(SIDs[0]);SIDi=0;
#ifdef DEMO
			nexti=(nexti+1)&7;
			if (nexti==0) i=0;
			else if ((nexti>2)&&(nexti!=4)) i=vyber_sid(nexti);
			else
#endif
			i=1;
			break;
		    } else {	//vypadava 1
			i=vyber_sid(5);
		    }
		    break;
		} else {
		    SIDaddr=(char *)(SIDs[2]);SIDi=2;
		    p=get_p();
		    q=get_q();
		    if ((p!='s')||(q!='w')) {	//vypadava 2
			i=vyber_sid(3);
		    } else {	//zustava 0,1 a 2
			SIDaddr=(char *)(SIDs[2]);SIDi=2;
			sidoffon();
			SIDaddr=(char *)(SIDs[1]);SIDi=1;
			p=get_p();
			q=get_q();
			if ((p!='s')||(q!='w')) {
			    i=vyber_sid(3);
			} else {
			    i=vyber_sid(7);
			}
		    }
		    break;
		}
		break;
	default:i=0;
		break;
    }
    if (i>0) {
		printf_sidi();
    } else {
		cputs(Notfou);
		cputs("\r\n");
    }
    return i;
}

//details printing
void details() {
    unsigned char p,q;
	p=get_pcmd('v','i');
    q=get_q();
#ifdef DEMO
    p=3;
    q=6;
#endif
    version=p;
    cputs ("fw version:");
    cputbval(p);
    cputc('.');
    cputbval(q);
	cputs ("\r\n");
	p=get_pcmd('f','i');
    if ((p<=32)||(p>127)) p='.';
    q=get_q();if ((q<=32)||(q>127)) q='.';
#ifdef DEMO
    p='8';
    q='5';
#endif
    if (version>=2) {
	cputs ("emulated device:");
    cputc(p);
    cputc(q);
	cputs ("xx");
	p=get_pcmd('g','i');
	if (p=='7') cputs ("(auto detected)\r\n");
	else cputs ("               \r\n");
    } else {
	cputs ("emulated device:");
    cputc(p);
    cputc(q);
	cputs ("xx\r\n");
    }
	p=get_pcmd('i','f');
    if ((p<=32)||(p>127)) p='.';
    q=get_q();if ((q<=32)||(q>127)) q='.';
#ifdef DEMO
    p='a';
    q='p';
#endif
    cputs ("app/boot:");
    cputc(p);
    cputc(q);
    cputs("\r\n\r\n\r\n\r\n\r\n\r\npress ");
	cputs2("@6/@7/@8 to 6581/auto/8580 emulation\r\npress ");
    if (version>=2) {
		cputs2("@p to permanently save\r\npress @e to extended menu ...\r\npress ");
    }
	if (isARM2) {
		cputs2("@m to address mapping configurationpress ");
	}
	cputs2("@r to restart the tester\r\nand @q to quit\r\n");
    if (version>=2) {
    } else {
    	cputs ("  upgrade firmware to version 2.0 and\r\n      newer for new features !!!\r\n");
    }
    gotoy(10);
}

#ifdef DEMO
#define napeti 9123
char napeti_zmena=0;
#endif

//analog values test
void analog() {
    unsigned char x,y;
    int v;
    x=SIDaddr[25];
    y=SIDaddr[26];
    ((char*)&v)[1]=get_pcmd('u','i');
    ((char*)&v)[0]=get_q();
#ifdef DEMO
    x=101;
    y=255;
    ((char*)&v)[1]=napeti/256;
    ((char*)&v)[0]=napeti%256;
    napeti_zmena^=1;
    if (napeti_zmena) napeti_zmena-=1;
#endif
    cputs("potx=");
    cputbval(x);
    cputs("  \r\npoty=");
    cputbval(y);
    cputs("  \r\nvdd=");
    cput1000(v);
    cputs(" v    \r\n");
    gotoy(wherey()-3);
}

//filter setting reading
void nacti_extend() {
    unsigned char p,q;
    signed char v;
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

//memory mapping reading
void nacti_mem() {
    unsigned char p,q;
	p=get_pcmd('m','m');
    q=get_q();
    mem_emul=p&7;
    if (mem_emul&4) ntsc=4; else ntsc=0;
    if ((mem_emul&3)==3) mem_emul==1;
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
#ifdef DEMO
	mem_value[0]=1;
	mem_value[1]=2;
	mem_value[2]=2;
	mem_value[3]=1;
	mem_value[4]=0;
	mem_value[5]=0;
	mem_value[6]=0;
	mem_value[7]=0;
	ntsc=0;
	socket=0;
	mem_emul=0;
	downM=0;
#endif
}

//saving configuration to the ram or permanently to the flash memory of ARMSID
void save(char jak) {
    char i;
    clrscr();
    uvod();
    switch(jak) {
	case 's':
	    gotoxy(13,12);
	    cputs("saving to ram");
	        SIDaddr[31]=0xC0;
		SIDaddr[30]='e';
	    gotoxy(13,13);
	    for(i=0;i<13;i++) {
		delay(1000/13);
		cputc('#');
	    }
	break;
	case 'p':
	    gotoxy(12,12);
	    cputs("saving to flash");
	        SIDaddr[31]=0xCF;
		SIDaddr[30]='e';
	    gotoxy(12,13);
	    for(i=0;i<15;i++) {
		delay(2000/15);
		cputc('#');
	    }
	break;
	default:break;
    }
}

//extended page (filter setting) automaton
char extended() {
    char key;
    uvod_extend();
    while (1) {
    	if (kbhit()) {
			key=cgetc();
			if ((key=='q')||(key=='b')) return key;
			if ((key=='s')||(key=='p')) {
				{
					unsigned char i=0;
					while (i<4) {
						SIDaddr[31]=0x80|(i<<4)|(vyber_value[i]&15);
						SIDaddr[30]='e';
						delay(10);
						i++;
					}
				}
			}
			if (key=='s') {
			save(key);
			return 0;
			}
			if (key=='p') {
			save(key);
			return 0;
			}
			vyber_zmena(key,1);
		}
    }
}

//memory mapping page automaton
char mem() {
    char key;
    uvod_mem();
    while (1) {
    	if (kbhit()) {
			key=cgetc();
			if ((key=='q')||(key=='b')) return key;
			if ((key=='s')||(key=='p')) {
				SIDaddr[31]='0'+(mem_emul)+((mem_emul)?(ntsc):0);
				SIDaddr[30]='m';
				delay(10);
				SIDaddr[31]=((downM)?'r':'s');
				SIDaddr[30]='m';
				delay(10);
				SIDaddr[31]=((socket)?'e':'c');
				SIDaddr[30]='m';
				delay(10);
				{
					unsigned char i=0;
					while (i<8) {
						SIDaddr[31]=0x80|(i<<4)|(mem_value[i]&15);
						SIDaddr[30]='m';
						delay(10);
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

int main (void)
{
    char a=0;
    *(unsigned char *)0xd018 = 0x15;	//just uppercase letters
    while (a!='q') {
	a=0;
	uvod();
	if (!najdi()) return EXIT_SUCCESS;
	while ((a!='q')&&(a!='r')) {
	    uvod();
	    if (!najdi2()) return EXIT_SUCCESS;
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
			SIDaddr[31]=a;
			SIDaddr[30]='e';
			delay(10);
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
	cputs ("\r\n\r\n\r\n\r\n\r\n\r\n");
	sid_off();
    }
    return EXIT_SUCCESS;
}

