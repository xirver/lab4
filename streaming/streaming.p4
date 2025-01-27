/* -*- P4_16 -*- */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;
const bit<8> IP_PROTO_UDP= 0x11;

/*************************************************************************
*********************** H E A D E R S  ***********************************
*************************************************************************/

/* define packet headers for Ethernet, IPv4, UDP, and RTP */
typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
  macAddr_t dstAddr;
  macAddr_t srcAddr;
  bit<16>   etherType;
}

header ipv4_t {
  /* TODO */
  bit<4>    version;
  bit<4>    ihl;
  bit<8>    diffserv;
  bit<16>   totalLen;
  bit<16>   identification;
  bit<3>    flags;
  bit<13>   fragOffset;
  bit<8>    ttl;
  bit<8>    protocol;
  bit<16>   hdrChecksum;
  ip4Addr_t srcAddr;
  ip4Addr_t dstAddr;
  varbit<320>  options;
}

header IPv4_up_to_ihl_only_h {
  bit<4>       version;
  bit<4>       ihl;
}

header udp_t {
  bit<16> srcPort;
  bit<16> dstPort;
  bit<16> length_;
  bit<16> checksum;
}

header rtp_t {
  bit<2> version;
  bit<1> padding;
  bit<1> extension;
  bit<4> CSRC_count;
  bit<1> marker;
  bit<7> payload_type;
  bit<16> sequence_number;
  bit<32> timestamp;
  bit<32> SSRC;
}

struct metadata {
  /* empty */
  bit<16>     l4Len;
}

struct headers {
  ethernet_t  ethernet;
  ipv4_t      ipv4;
  udp_t       udp;
  rtp_t       rtp;         
}

/*************************************************************************
*********************** P A R S E R  ***********************************
*************************************************************************/

parser MyParser(packet_in packet, out headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {

  state start {
    /* parse packet headers up to RTP if possible */
    transition parse_ethernet;
  }
  
  state parse_ethernet {
    /* TODO */
    packet.extract(hdr.ethernet);
    transition select(hdr.ethernet.etherType) {
      TYPE_IPV4: parse_ipv4;
      default: accept;
    }
  }

  state parse_ipv4 {
    packet.extract(hdr.ipv4, (bit<32>) (8 * (4 * (bit<9>) (packet.lookahead<IPv4_up_to_ihl_only_h>().ihl) - 20)));
    meta.l4Len = hdr.ipv4.totalLen - (bit<16>)(hdr.ipv4.ihl)*4;
    transition select (hdr.ipv4.protocol) {
      17: parse_udp;
      default: accept;
    }
  }

  state parse_udp {
    packet.extract(hdr.udp);
    transition accept;
  }

  state parse_rtp {            
    packet.extract(hdr.rtp);
    transition accept;
  }
 
}

/*************************************************************************
************   C H E C K S U M    V E R I F I C A T I O N   *************
*************************************************************************/

control MyVerifyChecksum(inout headers hdr, inout metadata meta) {   
  apply {  
    verify_checksum(
      hdr.ipv4.isValid(),
      { 
      hdr.ipv4.version,
      hdr.ipv4.ihl,
      hdr.ipv4.diffserv,
      hdr.ipv4.totalLen,
      hdr.ipv4.identification,
      hdr.ipv4.flags,
      hdr.ipv4.fragOffset,
      hdr.ipv4.ttl,
      hdr.ipv4.protocol,
      hdr.ipv4.srcAddr,
      hdr.ipv4.dstAddr,
      hdr.ipv4.options
      },
      hdr.ipv4.hdrChecksum,
      HashAlgorithm.csum16);

    verify_checksum_with_payload(
      hdr.udp.isValid(),
      { 
      hdr.ipv4.srcAddr,
      hdr.ipv4.dstAddr,
      8w0,
      hdr.ipv4.protocol,
      meta.l4Len,
      hdr.udp.srcPort,
      hdr.udp.dstPort,
      hdr.udp.length_
      },
      hdr.udp.checksum,
      HashAlgorithm.csum16);
  }
}

/*************************************************************************
**************  I N G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyIngress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {

  action drop(){
    mark_to_drop(standard_metadata);
  }
    
    
  action multicast() {
    standard_metadata.mcast_grp = 1;
  }

  action multicast_mod(macAddr_t dstAddr, macAddr_t srcAddr, ip4Addr_t dst_ip){
    standard_metadata.mcast_grp = 1;
    hdr.ethernet.srcAddr=srcAddr;
    hdr.ethernet.dstAddr=dstAddr;
    hdr.ipv4.dstAddr=dst_ip;
    hdr.ipv4.ttl=hdr.ipv4.ttl-1;
  }

  action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
    /* TODO */
    standard_metadata.egress_spec = port;
    hdr.ethernet.srcAddr=hdr.ethernet.dstAddr;
    hdr.ethernet.dstAddr=dstAddr;
    hdr.ipv4.ttl=hdr.ipv4.ttl-1;
  }


  table _multi{
    key = {
      hdr.ipv4.dstAddr: lpm;
      hdr.ipv4.srcAddr: exact;
    }
    actions={
      multicast;
      multicast_mod;
      NoAction;
    }
    size=1024;
    default_action = NoAction();
  }

  table ipv4_lpm {
    /* TODO */
    key = {
      hdr.ipv4.dstAddr: lpm;
    }
    actions = {
      ipv4_forward;
      drop;
      NoAction;
    }
    size=1024;
    default_action = NoAction();
  }

  apply {
    if (hdr.ipv4.isValid()) {
      ipv4_lpm.apply();
      _multi.apply();
    }
  }
}

/*************************************************************************
****************  E G R E S S   P R O C E S S I N G   *******************
*************************************************************************/

control MyEgress(inout headers hdr, inout metadata meta, inout standard_metadata_t standard_metadata) {
  
  action drop() {
    mark_to_drop(standard_metadata);
  }

  apply {  
    
  }
}

/*************************************************************************
*************   C H E C K S U M    C O M P U T A T I O N   **************
*************************************************************************/

control MyComputeChecksum(inout headers hdr, inout metadata meta) {
  apply{
    update_checksum(
      hdr.ipv4.isValid(),
      { 
      hdr.ipv4.version,
      hdr.ipv4.ihl,
      hdr.ipv4.diffserv,
      hdr.ipv4.totalLen,
      hdr.ipv4.identification,
      hdr.ipv4.flags,
      hdr.ipv4.fragOffset,
      hdr.ipv4.ttl,
      hdr.ipv4.protocol,
      hdr.ipv4.srcAddr,
      hdr.ipv4.dstAddr,
      hdr.ipv4.options 
      },
      hdr.ipv4.hdrChecksum,
      HashAlgorithm.csum16);

    update_checksum_with_payload(
      hdr.udp.isValid(),
      { 
      hdr.ipv4.srcAddr,
      hdr.ipv4.dstAddr,
      8w0,
      hdr.ipv4.protocol,
      meta.l4Len,
      hdr.udp.srcPort,
      hdr.udp.dstPort,
      hdr.udp.length_
      },
      hdr.udp.checksum,
      HashAlgorithm.csum16);
  }
}

/*************************************************************************
***********************  D E P A R S E R  *******************************
*************************************************************************/

control MyDeparser(packet_out packet, in headers hdr) {
  apply {
    packet.emit(hdr.ethernet);
    packet.emit(hdr.ipv4);
    packet.emit(hdr.udp);
    packet.emit(hdr.rtp);
  }
}

/*************************************************************************
***********************  S W I T C H  *******************************
*************************************************************************/

V1Switch(
MyParser(),
MyVerifyChecksum(),
MyIngress(),
MyEgress(),
MyComputeChecksum(),
MyDeparser()
) main;
