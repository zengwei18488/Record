#include <linux/device.h>
#include <linux/delay.h>
#include <linux/phy/phy.h>
#include <soc/rockchip/rockchip_phy_typec.h>

#include "cdn-dp-core.h"
#include "cdn-dp-reg.h"

static void cdn_dp_set_signal(struct cdn_dp_device *dp)
{
	struct cdn_dp_port *port = dp->port[dp->active_port];
	struct rockchip_typec_phy *tcphy = phy_get_drvdata(port->phy);

	int rate = drm_dp_bw_code_to_link_rate(dp->link.rate);
	u8 swing = (dp->train_set[0] & DP_TRAIN_VOLTAGE_SWING_MASK) >>
		   DP_TRAIN_VOLTAGE_SWING_SHIFT;
	u8 pre_emphasis = (dp->train_set[0] & DP_TRAIN_PRE_EMPHASIS_MASK)
			  >> DP_TRAIN_PRE_EMPHASIS_SHIFT;

	tcphy->typec_phy_config(port->phy, rate, dp->link.num_lanes,
				swing, pre_emphasis);
}

static int cdn_dp_set_dp_config(struct cdn_dp_device *dp, uint8_t dp_train_pat)
{
	u32 phy_config, global_config;
	int ret;
	uint8_t pattern = dp_train_pat & DP_TRAINING_PATTERN_MASK;

	global_config = NUM_LANES(dp->link.num_lanes - 1) | SST_MODE |
			GLOBAL_EN | RG_EN | ENC_RST_DIS | WR_VHSYNC_FALL;

	phy_config = DP_TX_PHY_ENCODER_BYPASS(0) |
		     DP_TX_PHY_SKEW_BYPASS(0) |
		     DP_TX_PHY_DISPARITY_RST(0) |
		     DP_TX_PHY_LANE0_SKEW(0) |
		     DP_TX_PHY_LANE1_SKEW(1) |
		     DP_TX_PHY_LANE2_SKEW(2) |
		     DP_TX_PHY_LANE3_SKEW(3) |
		     DP_TX_PHY_10BIT_ENABLE(0);

	if (pattern != DP_TRAINING_PATTERN_DISABLE) {
		global_config |= NO_VIDEO;
		phy_config |= DP_TX_PHY_TRAINING_ENABLE(1) |
			      DP_TX_PHY_SCRAMBLER_BYPASS(1) |
			      DP_TX_PHY_TRAINING_PATTERN(pattern);
	}

	ret = cdn_dp_reg_write(dp, DP_FRAMER_GLOBAL_CONFIG, global_config);
	if (ret) {
		DRM_ERROR("fail to set DP_FRAMER_GLOBAL_CONFIG, error: %d\n",
			  ret);
		return ret;
	}

	ret = cdn_dp_reg_write(dp, DP_TX_PHY_CONFIG_REG, phy_config);
	if (ret) {
		DRM_ERROR("fail to set DP_TX_PHY_CONFIG_REG, error: %d\n",
			  ret);
		return ret;
	}

	ret = cdn_dp_reg_write(dp, DPTX_LANE_EN, BIT(dp->link.num_lanes) - 1);
	if (ret) {
		DRM_ERROR("fail to set DPTX_LANE_EN, error: %d\n", ret);
		return ret;
	}


		ret = cdn_dp_reg_write(dp, DPTX_ENHNCD, 1);

//		ret = cdn_dp_reg_write(dp, DPTX_ENHNCD, 0);
	if (ret)
		DRM_ERROR("failed to set DPTX_ENHNCD, error: %x\n", ret);

	return ret;
}


static int cdn_dp_set_link_signal_config(struct cdn_dp_device *dp,
				    uint8_t dp_train_pat)
{
	int ret;
 	u8 link_config[2];
 	
	memset(dp->train_set, 0, sizeof(dp->train_set));
  dp->train_set[0] = dp->force_swing | dp->force_pre_emphasis;//DP_TRAIN_PRE_EMPH_LEVEL_1|DP_TRAIN_VOLTAGE_SWING_LEVEL_1
  dp->link.num_lanes = dp->force_lanes;
  dp->link.rate = dp->force_rate;
  
  printk("force oute swing & pre-emphasis = %d,%d,lanes = %d,rate =%d",dp->force_swing, dp->force_pre_emphasis, dp->force_lanes, dp->force_rate);	
  link_config[0] = dp->link.rate;
	link_config[1] = dp->link.num_lanes;
//	if (drm_dp_enhanced_frame_cap(dp->dpcd))
	link_config[1] |= DP_LANE_COUNT_ENHANCED_FRAME_EN;
	drm_dp_dpcd_write(&dp->aux, DP_LINK_BW_SET, link_config, 2);
	ret = drm_dp_dpcd_write(&dp->aux, DP_TRAINING_LANE0_SET,
				dp->train_set, dp->link.num_lanes);
  
	cdn_dp_set_signal(dp);

	ret = cdn_dp_set_dp_config(dp, dp_train_pat);
	if (ret)
		return ret;

	return 0;
}


int cdn_dp_link_force_out(struct cdn_dp_device *dp)
{

	int ret;
  printk("gln cdn_dp_link_force_out\n");
	ret = cdn_dp_set_link_signal_config(dp, DP_TRAINING_PATTERN_DISABLE |
					  DP_LINK_SCRAMBLING_DISABLE);
	if (ret) {
		DRM_ERROR("failed to start link train\n");
		return ret;
	}

	return  ret;
}

