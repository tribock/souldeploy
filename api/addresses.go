package api

import (
	"bytes"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/imdario/mergo"
	"github.com/sirupsen/logrus"
	"github.com/tribock/go-via/db"
	"github.com/tribock/go-via/models"
	"gorm.io/gorm"
)

// ListAddresses Get a list of all addresses
// @Summary Get all addresses
// @Tags addresses
// @Accept  json
// @Produce  json
// @Success 200 {array} models.Address
// @Failure 500 {object} models.APIError
// @Router /addresses [get]
func ListAddresses(c *gin.Context) {
	var items []models.Address
	if res := db.DB.Preload("Pool").Find(&items); res.Error != nil {
		Error(c, http.StatusInternalServerError, res.Error) // 500
		return
	}
	c.JSON(http.StatusOK, items) // 200
}

// GetAddress Get an existing address
// @Summary Get an existing address
// @Tags addresses
// @Accept  json
// @Produce  json
// @Param  id path int true "Address ID"
// @Success 200 {object} models.Address
// @Failure 400 {object} models.APIError
// @Failure 404 {object} models.APIError
// @Failure 500 {object} models.APIError
// @Router /addresses/{id} [get]
func GetAddress(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		Error(c, http.StatusBadRequest, err) // 400
		return
	}

	// Load the item
	var item models.Address
	if res := db.DB.Preload("Pool").First(&item, id); res.Error != nil {
		if errors.Is(res.Error, gorm.ErrRecordNotFound) {
			Error(c, http.StatusNotFound, fmt.Errorf("not found")) // 404
		} else {
			Error(c, http.StatusInternalServerError, res.Error) // 500
		}
		return
	}

	c.JSON(http.StatusOK, item) // 200
}

// SearchAddress Search for an address
// @Summary Search for an address
// @Tags addresses
// @Accept  json
// @Produce  json
// @Param item body models.Address true "Fields to search for"
// @Success 200 {object} models.Address
// @Failure 400 {object} models.APIError
// @Failure 404 {object} models.APIError
// @Failure 500 {object} models.APIError
// @Router /addresses/search [post]
func SearchAddress(c *gin.Context) {
	form := make(map[string]interface{})

	if err := c.ShouldBind(&form); err != nil {
		Error(c, http.StatusBadRequest, err) // 400
		return
	}

	query := db.DB

	for k, v := range form {
		query = query.Where(k, v)
	}

	// Load the item
	var item models.Address
	if res := query.Preload("Pool").First(&item); res.Error != nil {
		if errors.Is(res.Error, gorm.ErrRecordNotFound) {
			Error(c, http.StatusNotFound, fmt.Errorf("not found")) // 404
		} else {
			Error(c, http.StatusInternalServerError, res.Error) // 500
		}
		return
	}

	c.JSON(http.StatusOK, item) // 200
}

// CreateAddress Create a new addresses
// @Summary Create a new addresses
// @Tags addresses
// @Accept  json
// @Produce  json
// @Param item body models.AddressForm true "Add ip address"
// @Success 200 {object} models.Address
// @Failure 400 {object} models.APIError
// @Failure 500 {object} models.APIError
// @Router /addresses [post]
func CreateAddress(c *gin.Context) {
	var form models.AddressForm

	if err := c.ShouldBind(&form); err != nil {
		Error(c, http.StatusBadRequest, err) // 400
		return
	}

	item := models.Address{AddressForm: form}

	// get the pool network info to verify if this ip should be added to the pool.
	var na models.Pool
	db.DB.First(&na, "id = ?", item.AddressForm.PoolID)

	cidr := item.IP + "/" + strconv.Itoa(na.Netmask)
	network := na.NetAddress + "/" + strconv.Itoa(na.Netmask)

	// first check if the address is even in the network.
	_, neta, _ := net.ParseCIDR(network)
	ipb, _, _ := net.ParseCIDR(cidr)
	start := net.ParseIP(na.StartAddress)
	end := net.ParseIP(na.EndAddress)
	if neta.Contains(ipb) {
		//then check if it's in the given range by the pool.
		trial := net.ParseIP(item.IP)

		if bytes.Compare(trial, start) >= 0 && bytes.Compare(trial, end) <= 0 {
			logrus.WithFields(logrus.Fields{
				"ip":    trial,
				"start": start,
				"end":   end,
			}).Debug("ip validation successful")
		} else {
			logrus.WithFields(logrus.Fields{
				"ip":    trial,
				"start": start,
				"end":   end,
			}).Debug("the ip address is not in the scope of the dhcp pool associated with the group")
			Error(c, http.StatusBadRequest, fmt.Errorf("the ip address is not in the scope of the dhcp pool associated with the group")) // 400
			return
		}
	} else {
		Error(c, http.StatusBadRequest, fmt.Errorf("the ip address is not in the scope of the dhcp pool associated with the group")) // 400
		return
	}

	// ensure the mac address is properly formated.
	mac, _ := net.ParseMAC(item.Mac)
	item.Mac = mac.String()

	// if ip address checks pas, continue to commit.
	if item.ID != 0 { // Save if its an existing item
		if res := db.DB.Save(&item); res.Error != nil {
			Error(c, http.StatusInternalServerError, res.Error) // 500
			return
		}
	} else { // Create a new item
		if res := db.DB.Create(&item); res.Error != nil {
			Error(c, http.StatusInternalServerError, res.Error) // 500
			return
		}
	}

	// Load a new version with relations
	if res := db.DB.Preload("Pool").First(&item); res.Error != nil {
		Error(c, http.StatusInternalServerError, res.Error) // 500
		return
	}

	c.JSON(http.StatusOK, item) // 200

	logrus.WithFields(logrus.Fields{
		"Hostname": item.Hostname,
		"Domain":   item.Domain,
		"IP":       item.IP,
		"MAC":      item.Mac,
		"Pool ID":  item.PoolID,
		"Group ID": item.GroupID,
	}).Debug("host")
}

// UpdateAddress Update an existing address
// @Summary Update an existing address
// @Tags addresses
// @Accept  json
// @Produce  json
// @Param  id path int true "Address ID"
// @Param  item body models.AddressForm true "Update an ip address"
// @Success 200 {object} models.Address
// @Failure 400 {object} models.APIError
// @Failure 404 {object} models.APIError
// @Failure 500 {object} models.APIError
// @Router /addresses/{id} [patch]
func UpdateAddress(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		Error(c, http.StatusBadRequest, err) // 400
		return
	}

	// Load the form data
	var form models.AddressForm
	if err := c.ShouldBind(&form); err != nil {
		Error(c, http.StatusBadRequest, err) // 400
		return
	}

	// Load the item
	var item models.Address
	if res := db.DB.First(&item, id); res.Error != nil {
		if errors.Is(res.Error, gorm.ErrRecordNotFound) {
			Error(c, http.StatusNotFound, fmt.Errorf("not found")) // 404
		} else {
			Error(c, http.StatusInternalServerError, res.Error) // 500
		}
		return
	}

	// Merge the item and the form data
	if err := mergo.Merge(&item, models.Address{AddressForm: form}, mergo.WithOverride); err != nil {
		Error(c, http.StatusInternalServerError, err) // 500
	}

	// Mergo doesn't overwrite 0 or false values, force set
	item.AddressForm.Reimage = form.Reimage
	item.AddressForm.Progress = form.Progress

	// Save it
	if res := db.DB.Save(&item); res.Error != nil {
		Error(c, http.StatusInternalServerError, res.Error) // 500
		return
	}

	// Load a new version with relations
	if res := db.DB.Preload("Pool").First(&item); res.Error != nil {
		Error(c, http.StatusInternalServerError, res.Error) // 500
		return
	}

	c.JSON(http.StatusOK, item) // 200
}

// DeleteAddress Remove an existing address
// @Summary Remove an existing address
// @Tags addresses
// @Accept  json
// @Produce  json
// @Param  id path int true "Address ID"
// @Success 204
// @Failure 404 {object} models.APIError
// @Failure 500 {object} models.APIError
// @Router /addresses/{id} [delete]
func DeleteAddress(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		Error(c, http.StatusBadRequest, err) // 400
		return
	}

	// Load the item
	var item models.Address
	if res := db.DB.First(&item, id); res.Error != nil {
		if errors.Is(res.Error, gorm.ErrRecordNotFound) {
			Error(c, http.StatusNotFound, fmt.Errorf("not found")) // 404
		} else {
			Error(c, http.StatusInternalServerError, res.Error) // 500
		}
		return
	}

	// delete it
	if res := db.DB.Delete(&item); res.Error != nil {
		Error(c, http.StatusInternalServerError, res.Error) // 500
		return
	}

	c.JSON(http.StatusNoContent, gin.H{}) //204
}
